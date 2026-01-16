import express from 'express';
import cors from 'cors';
import path from 'path';
import { exec, spawn } from 'child_process';
import { promisify } from 'util';
import { execSync } from 'child_process';

const execAsync = promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;

// Get repository root and database path
const REPO_ROOT = execSync('git rev-parse --show-toplevel', { encoding: 'utf-8' }).trim();
const DB_PATH = process.env.DB_PATH || path.join(REPO_ROOT, '.pr_monitor', 'data', 'pr_tracking.db');

// Auto-detect GitHub repo from git remote
function getGitHubRepo(): string {
  try {
    const remote = execSync('git remote get-url origin', { encoding: 'utf-8' }).trim();
    const match = remote.match(/github\.com[:/](.+?)(?:\.git)?$/);
    return match ? match[1].replace(/\.git$/, '') : '';
  } catch {
    return '';
  }
}

const GITHUB_REPO = process.env.GITHUB_REPO || getGitHubRepo();

// Track spawned monitor PIDs for cleanup
const monitorPids = new Set<number>();

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' })); // Increased limit for large workflow data
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use(express.static(path.join(__dirname, '../public')));

// Request logging (for debugging)
app.use((req, res, next) => {
  if (req.method !== 'GET') {
    const contentLength = req.headers['content-length'] || '0';
    console.log(`${req.method} ${req.path} - Content-Length: ${contentLength} bytes`);
  }
  next();
});

// Error handler for payload too large
app.use((err: any, req: any, res: any, next: any) => {
  if (err.type === 'entity.too.large') {
    console.error(`Payload too large for ${req.method} ${req.path}`);
    console.error(`Content-Length: ${req.headers['content-length']} bytes`);
    return res.status(413).json({
      success: false,
      error: 'Payload too large',
      message: 'The request payload exceeds the maximum allowed size (50MB)'
    });
  }
  next(err);
});

// Helper to run sqlite commands
async function querySqlite(query: string): Promise<string> {
  try {
    const { stdout } = await execAsync(`sqlite3 -json "${DB_PATH}" "${query}"`);
    return stdout.trim();
  } catch (error) {
    console.error('SQLite query error:', error);
    return '[]';
  }
}

// Helper to get running monitors
async function getRunningMonitors() {
  try {
    const { stdout } = await execAsync('ps aux | grep "check_pr_status.sh" | grep -v grep');
    const lines = stdout.trim().split('\n').filter((line: string) => line.length > 0);

    return lines.map((line: string) => {
      const parts = line.split(/\s+/);
      const command = parts.slice(10).join(' ');
      const prMatch = command.match(/check_pr_status\.sh\s+(\d+)(?:\s+([^\s]+))?/);

      return {
        pid: parseInt(parts[1]),
        pr_number: prMatch ? parseInt(prMatch[1]) : 0,
        repo: prMatch && prMatch[2] ? prMatch[2] : 'unknown',
        cpu: parts[2],
        mem: parts[3],
        time: parts[9],
        command
      };
    });
  } catch (error) {
    return [];
  }
}

// Helper to check if a monitor is already running for a PR
async function isMonitorRunning(prNumber: number, repo?: string): Promise<boolean> {
  const monitors = await getRunningMonitors();

  return monitors.some(monitor => {
    if (monitor.pr_number !== prNumber) return false;
    // If repo is specified, check it matches too
    if (repo && monitor.repo !== repo && monitor.repo !== 'unknown') return false;
    return true;
  });
}

// API Routes
app.get('/api/monitors', async (req, res) => {
  const monitors = await getRunningMonitors();
  res.json({ success: true, monitors });
});

// Get log file for a PR
app.get('/api/logs/:prNumber', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const lines = parseInt(req.query.lines as string) || 100;
    const offset = parseInt(req.query.offset as string) || 0;

    const logPath = path.join(REPO_ROOT, '.pr_monitor', 'logs', `pr_${prNumber}.log`);

    // Check if log file exists
    const fs = require('fs');
    if (!fs.existsSync(logPath)) {
      return res.json({
        success: true,
        logs: '',
        exists: false,
        message: `No log file found for PR #${prNumber}. Monitor may not have started yet.`
      });
    }

    // Read last N lines of log file using tail
    const { stdout } = await execAsync(`tail -n ${lines + offset} "${logPath}" | head -n ${lines}`);

    // Get file size and line count for metadata
    const { stdout: lineCount } = await execAsync(`wc -l < "${logPath}"`);
    const { stdout: fileSize } = await execAsync(`stat -f%z "${logPath}" 2>/dev/null || stat -c%s "${logPath}" 2>/dev/null || echo "0"`);

    res.json({
      success: true,
      logs: stdout,
      exists: true,
      metadata: {
        total_lines: parseInt(lineCount.trim()),
        file_size_bytes: parseInt(fileSize.trim()),
        lines_returned: lines,
        log_path: logPath
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// Stream log file (for real-time updates)
app.get('/api/logs/:prNumber/tail', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const lines = parseInt(req.query.lines as string) || 50;

    const logPath = path.join(REPO_ROOT, '.pr_monitor', 'logs', `pr_${prNumber}.log`);

    // Check if log file exists
    const fs = require('fs');
    if (!fs.existsSync(logPath)) {
      return res.json({
        success: true,
        logs: `Waiting for monitor to start for PR #${prNumber}...\nLog file will appear at: ${logPath}`,
        exists: false
      });
    }

    // Get last N lines
    const { stdout } = await execAsync(`tail -n ${lines} "${logPath}"`);

    res.json({
      success: true,
      logs: stdout,
      exists: true,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// Detect PR for current branch
app.get('/api/detect-pr', async (req, res) => {
  try {
    const { stdout: branch } = await execAsync('git branch --show-current');
    const branchName = branch.trim();

    if (!branchName) {
      res.json({ success: false, error: 'Not on a branch' });
      return;
    }

    const { stdout: prData } = await execAsync(
      `gh pr list --head "${branchName}" --json number,title,url`
    );
    const prs = JSON.parse(prData.trim() || '[]');

    res.json({
      success: true,
      pr: prs[0] || null,
      branch: branchName
    });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// Start monitoring a PR
app.post('/api/monitors/start', async (req, res) => {
  try {
    const { pr_number, repo } = req.body;

    if (!pr_number) {
      res.status(400).json({ success: false, error: 'pr_number is required' });
      return;
    }

    // Use provided repo or fall back to detected repo
    const repoToUse = repo || GITHUB_REPO;

    if (!repoToUse) {
      res.status(400).json({
        success: false,
        error: 'Could not determine repository. Please provide repo parameter or set GITHUB_REPO environment variable.'
      });
      return;
    }

    // Check if monitor is already running for this PR
    const alreadyRunning = await isMonitorRunning(pr_number, repoToUse);
    if (alreadyRunning) {
      res.status(409).json({
        success: false,
        error: `Monitor is already running for PR #${pr_number}`,
        code: 'ALREADY_RUNNING'
      });
      return;
    }

    const scriptPath = path.join(REPO_ROOT, '.pr_monitor', 'scripts', 'check_pr_status.sh');

    // Spawn the monitoring script in detached mode with explicit repo argument
    const child = spawn(scriptPath, [String(pr_number), repoToUse], {
      detached: true,
      stdio: 'ignore',
      env: { ...process.env, GITHUB_REPO: repoToUse }
    });
    child.unref();

    // Track this PID for cleanup
    if (child.pid) {
      monitorPids.add(child.pid);
    }

    res.json({
      success: true,
      pid: child.pid,
      message: `Monitor started for PR #${pr_number} (${repoToUse})`
    });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.post('/api/monitors/stop/:pid', async (req, res) => {
  try {
    const pid = parseInt(req.params.pid);

    // Get the PR number from the process command line
    let prNumber = 0;
    try {
      const { stdout } = await execAsync(`ps -p ${pid} -o command=`);
      const prMatch = stdout.match(/check_pr_status\.sh\s+(\d+)/);
      if (prMatch) {
        prNumber = parseInt(prMatch[1]);
      }
    } catch (err) {
      // Process might already be dead, that's ok
    }

    // Try multiple approaches to ensure the process is killed
    const killAttempts = [];

    // 1. Kill the specific PID
    killAttempts.push(
      execAsync(`kill ${pid}`).catch(() => {})
    );

    // 2. Kill by process group
    killAttempts.push(
      execAsync(`kill -- -${pid}`).catch(() => {})
    );

    // 3. If we have the PR number, kill all matching processes
    if (prNumber > 0) {
      killAttempts.push(
        execAsync(`pkill -f "check_pr_status\\.sh\\s+${prNumber}"`).catch(() => {})
      );
    }

    // 4. Force kill after a moment
    await Promise.all(killAttempts);

    // Wait a bit then force kill if still running
    setTimeout(async () => {
      try {
        await execAsync(`kill -9 ${pid}`).catch(() => {});
        if (prNumber > 0) {
          await execAsync(`pkill -9 -f "check_pr_status\\.sh\\s+${prNumber}"`).catch(() => {});
        }
      } catch (err) {
        // Ignore - process is probably already dead
      }
    }, 500);

    res.json({ success: true, message: `Monitor stopped` });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs', async (req, res) => {
  try {
    const result = await querySqlite(`
      SELECT p.*,
        COUNT(DISTINCT c.id) as comment_count,
        SUM(CASE WHEN c.addressed = 0 THEN 1 ELSE 0 END) as unaddressed_comments,
        COUNT(DISTINCT w.id) as workflow_count,
        SUM(CASE WHEN w.conclusion = 'failure' THEN 1 ELSE 0 END) as failed_workflow_count
      FROM prs p
      LEFT JOIN comments c ON c.pr_id = p.id
      LEFT JOIN workflows w ON w.pr_id = p.id
      GROUP BY p.id
      ORDER BY p.updated_at DESC
    `);
    const prs = JSON.parse(result || '[]');
    res.json({ success: true, prs });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs/:prNumber', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;
    
    let query = `SELECT * FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) query += ` AND repo = '${repo}'`;
    
    const result = await querySqlite(query);
    const prs = JSON.parse(result || '[]');
    
    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }
    
    res.json({ success: true, pr: prs[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs/:prNumber/comments', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;
    
    let prQuery = `SELECT id FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) prQuery += ` AND repo = '${repo}'`;
    
    const prResult = await querySqlite(prQuery);
    const prs = JSON.parse(prResult || '[]');
    
    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }
    
    const result = await querySqlite(`SELECT * FROM comments WHERE pr_id = ${prs[0].id} ORDER BY created_at DESC`);
    const comments = JSON.parse(result || '[]');
    
    res.json({ success: true, comments });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs/:prNumber/workflows', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;

    let prQuery = `SELECT id FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) prQuery += ` AND repo = '${repo}'`;

    const prResult = await querySqlite(prQuery);
    const prs = JSON.parse(prResult || '[]');

    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    // Get workflows with job counts
    const result = await querySqlite(`
      SELECT
        w.*,
        COUNT(j.id) as job_count,
        SUM(CASE WHEN j.conclusion = 'failure' THEN 1 ELSE 0 END) as failed_job_count,
        SUM(CASE WHEN j.conclusion = 'success' THEN 1 ELSE 0 END) as successful_job_count,
        SUM(CASE WHEN j.status = 'in_progress' THEN 1 ELSE 0 END) as in_progress_job_count
      FROM workflows w
      LEFT JOIN workflow_jobs j ON j.workflow_id = w.id
      WHERE w.pr_id = ${prs[0].id}
      GROUP BY w.id
      ORDER BY w.created_at DESC
    `);
    const workflows = JSON.parse(result || '[]');

    res.json({ success: true, workflows });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/workflows/:workflowId/jobs', async (req, res) => {
  try {
    const workflowId = parseInt(req.params.workflowId);

    const result = await querySqlite(`
      SELECT * FROM workflow_jobs
      WHERE workflow_id = ${workflowId}
      ORDER BY
        CASE conclusion
          WHEN 'failure' THEN 1
          WHEN 'cancelled' THEN 2
          WHEN 'success' THEN 3
          ELSE 4
        END,
        created_at ASC
    `);
    const jobs = JSON.parse(result || '[]');

    res.json({ success: true, jobs });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs/:prNumber/failed-jobs', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;

    let prQuery = `SELECT id FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) prQuery += ` AND repo = '${repo}'`;

    const prResult = await querySqlite(prQuery);
    const prs = JSON.parse(prResult || '[]');

    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    // Get all failed jobs with workflow info
    const result = await querySqlite(`
      SELECT
        j.*,
        w.workflow_name,
        w.run_number,
        w.html_url as workflow_url,
        w.status as workflow_status,
        w.conclusion as workflow_conclusion
      FROM workflow_jobs j
      JOIN workflows w ON w.id = j.workflow_id
      WHERE j.pr_id = ${prs[0].id} AND j.conclusion = 'failure'
      ORDER BY j.completed_at DESC
    `);
    const failedJobs = JSON.parse(result || '[]');

    res.json({ success: true, failed_jobs: failedJobs });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs/:prNumber/workflow-summary', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;

    let prQuery = `SELECT id FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) prQuery += ` AND repo = '${repo}'`;

    const prResult = await querySqlite(prQuery);
    const prs = JSON.parse(prResult || '[]');

    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    // Get workflow summary statistics
    const workflowStats = await querySqlite(`
      SELECT
        COUNT(DISTINCT w.id) as total_workflows,
        SUM(CASE WHEN w.conclusion = 'success' THEN 1 ELSE 0 END) as successful_workflows,
        SUM(CASE WHEN w.conclusion = 'failure' THEN 1 ELSE 0 END) as failed_workflows,
        SUM(CASE WHEN w.status = 'in_progress' THEN 1 ELSE 0 END) as in_progress_workflows,
        SUM(CASE WHEN w.status = 'queued' THEN 1 ELSE 0 END) as queued_workflows
      FROM workflows w
      WHERE w.pr_id = ${prs[0].id}
    `);

    const jobStats = await querySqlite(`
      SELECT
        COUNT(*) as total_jobs,
        SUM(CASE WHEN conclusion = 'success' THEN 1 ELSE 0 END) as successful_jobs,
        SUM(CASE WHEN conclusion = 'failure' THEN 1 ELSE 0 END) as failed_jobs,
        SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress_jobs
      FROM workflow_jobs
      WHERE pr_id = ${prs[0].id}
    `);

    res.json({
      success: true,
      summary: {
        workflows: JSON.parse(workflowStats || '[]')[0] || {},
        jobs: JSON.parse(jobStats || '[]')[0] || {}
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// Get detailed errors for a PR (actionable for AI agents)
app.get('/api/prs/:prNumber/errors', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;

    let prQuery = `SELECT id FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) prQuery += ` AND repo = '${repo}'`;

    const prResult = await querySqlite(prQuery);
    const prs = JSON.parse(prResult || '[]');

    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    // Get all failed jobs with complete error details
    const result = await querySqlite(`
      SELECT
        j.job_id,
        j.job_name,
        j.status,
        j.conclusion,
        j.failed_steps,
        j.error_message,
        j.html_url as job_url,
        j.runner_name,
        j.completed_at,
        w.workflow_name,
        w.run_id,
        w.html_url as workflow_url,
        w.head_sha,
        w.run_number
      FROM workflow_jobs j
      JOIN workflows w ON w.id = j.workflow_id
      WHERE j.pr_id = ${prs[0].id} AND j.conclusion = 'failure'
      ORDER BY j.completed_at DESC
    `);

    const failedJobs = JSON.parse(result || '[]');

    // Parse failed_steps from JSON string to array
    const processedJobs = failedJobs.map((job: any) => {
      let failedSteps = [];
      try {
        failedSteps = job.failed_steps ? JSON.parse(job.failed_steps) : [];
      } catch (e) {
        failedSteps = [];
      }

      return {
        workflow: job.workflow_name,
        job: job.job_name,
        error: job.error_message,
        failed_steps: failedSteps,
        job_url: job.job_url,
        workflow_url: job.workflow_url,
        runner: job.runner_name,
        run_id: job.run_id,
        run_number: job.run_number,
        completed_at: job.completed_at
      };
    });

    // Group errors by workflow
    const errorsByWorkflow: { [key: string]: any[] } = {};
    processedJobs.forEach((job: any) => {
      if (!errorsByWorkflow[job.workflow]) {
        errorsByWorkflow[job.workflow] = [];
      }
      errorsByWorkflow[job.workflow].push(job);
    });

    res.json({
      success: true,
      pr_number: prNumber,
      total_failures: processedJobs.length,
      failed_jobs: processedJobs,
      errors_by_workflow: errorsByWorkflow
    });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/prs/:prNumber/activities', async (req, res) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string;
    
    let prQuery = `SELECT id FROM prs WHERE pr_number = ${prNumber}`;
    if (repo) prQuery += ` AND repo = '${repo}'`;
    
    const prResult = await querySqlite(prQuery);
    const prs = JSON.parse(prResult || '[]');
    
    if (prs.length === 0) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }
    
    const result = await querySqlite(`SELECT * FROM activities WHERE pr_id = ${prs[0].id} ORDER BY activity_time DESC LIMIT 100`);
    const activities = JSON.parse(result || '[]');
    
    res.json({ success: true, activities });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.post('/api/comments/:commentId/address', async (req, res) => {
  try {
    const commentId = parseInt(req.params.commentId);
    const { notes } = req.body;
    
    await execAsync(`sqlite3 "${DB_PATH}" "UPDATE comments SET addressed=1, addressed_at=CURRENT_TIMESTAMP, addressed_notes='${notes || 'Marked via dashboard'}' WHERE comment_id=${commentId}"`);
    
    res.json({ success: true, message: 'Comment marked as addressed' });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('/api/stats', async (req, res) => {
  try {
    const totalPrs = await querySqlite('SELECT COUNT(*) as count FROM prs');
    const openPrs = await querySqlite("SELECT COUNT(*) as count FROM prs WHERE state = 'open'");
    const totalComments = await querySqlite('SELECT COUNT(*) as count FROM comments');
    const unaddressed = await querySqlite('SELECT COUNT(*) as count FROM comments WHERE addressed = 0');
    
    res.json({
      success: true,
      stats: {
        total_prs: JSON.parse(totalPrs)[0],
        open_prs: JSON.parse(openPrs)[0],
        total_comments: JSON.parse(totalComments)[0],
        unaddressed_comments: JSON.parse(unaddressed)[0]
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// Graceful shutdown handler
async function gracefulShutdown(signal: string) {
  console.log(`\n📡 Received ${signal}, shutting down gracefully...`);

  try {
    // Get all running monitors
    const monitors = await getRunningMonitors();

    if (monitors.length > 0) {
      console.log(`🛑 Stopping ${monitors.length} running monitor(s)...`);

      // Stop all monitors
      for (const monitor of monitors) {
        try {
          console.log(`   Stopping monitor for PR #${monitor.pr_number} (PID: ${monitor.pid})...`);

          // Try graceful kill first
          try {
            process.kill(monitor.pid, 'SIGTERM');
          } catch (err) {
            // Process might already be gone
          }

          // Also try pkill by PR number for safety
          if (monitor.pr_number > 0) {
            await execAsync(`pkill -f "check_pr_status\\.sh\\s+${monitor.pr_number}"`).catch(() => {});
          }
        } catch (error) {
          console.error(`   Failed to stop PID ${monitor.pid}:`, error);
        }
      }

      // Wait a moment for processes to terminate
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Force kill any remaining processes
      for (const monitor of monitors) {
        try {
          process.kill(monitor.pid, 'SIGKILL');
        } catch (err) {
          // Already dead, ignore
        }
      }

      console.log('✅ All monitors stopped');
    }
  } catch (error) {
    console.error('Error during shutdown:', error);
  }

  console.log('👋 Goodbye!');
  process.exit(0);
}

// Register shutdown handlers
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

const server = app.listen(PORT, () => {
  console.log(`🚀 PR Monitor Dashboard running at http://localhost:${PORT}`);
  console.log(`📊 Database: ${DB_PATH}`);
  console.log(`📁 Repository: ${GITHUB_REPO || '(not detected)'}`);
  console.log(`\n💡 Press Ctrl+C to stop the dashboard and all running monitors`);
});
