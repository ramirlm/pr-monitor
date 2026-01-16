import express, { Request, Response } from 'express';
import cors from 'cors';
import path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import sqlite3 from 'sqlite3';
import { open, Database } from 'sqlite';
import os from 'os';

const execAsync = promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;
const DB_PATH = process.env.DB_PATH || path.join(os.homedir(), '.pr_monitor', 'pr_tracking.db');

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// Database connection
let db: Database<sqlite3.Database, sqlite3.Statement>;

async function initDatabase() {
  try {
    db = await open({
      filename: DB_PATH,
      driver: sqlite3.Database
    });
    console.log(`Connected to database at: ${DB_PATH}`);
  } catch (error) {
    console.error('Failed to connect to database:', error);
    process.exit(1);
  }
}

// Types
interface PRData {
  id: number;
  pr_number: number;
  repo: string;
  title: string;
  state: string;
  author: string;
  created_at: string;
  updated_at: string;
  url: string;
}

interface MonitorProcess {
  pid: number;
  pr_number: number;
  repo: string;
  cpu: string;
  mem: string;
  time: string;
  command: string;
}

interface Comment {
  id: number;
  comment_id: number;
  comment_type: string;
  author: string;
  body: string;
  file_path: string | null;
  created_at: string;
  addressed: number;
  addressed_at: string | null;
  addressed_notes: string | null;
}

interface Workflow {
  id: number;
  run_id: number;
  workflow_name: string;
  status: string;
  conclusion: string | null;
  created_at: string;
  completed_at: string | null;
  failure_details: string | null;
}

interface Activity {
  id: number;
  activity_type: string;
  activity_time: string;
  summary: string;
  details: string | null;
  actor: string;
}

// Helper: Get running monitors
async function getRunningMonitors(): Promise<MonitorProcess[]> {
  try {
    const { stdout } = await execAsync('ps aux | grep "check_pr_status.sh" | grep -v grep');
    const lines = stdout.trim().split('\n').filter(line => line.length > 0);

    return lines.map(line => {
      const parts = line.split(/\s+/);
      const command = parts.slice(10).join(' ');

      // Extract PR number and repo from command
      const prMatch = command.match(/check_pr_status\.sh\s+(\d+)(?:\s+([^\s]+))?/);
      const pr_number = prMatch ? parseInt(prMatch[1]) : 0;
      const repo = prMatch && prMatch[2] ? prMatch[2] : 'unknown';

      return {
        pid: parseInt(parts[1]),
        pr_number,
        repo,
        cpu: parts[2],
        mem: parts[3],
        time: parts[9],
        command
      };
    });
  } catch (error) {
    // No processes found or error
    return [];
  }
}

// API Routes

// GET /api/monitors - Get all running monitors
app.get('/api/monitors', async (req: Request, res: Response) => {
  try {
    const monitors = await getRunningMonitors();
    res.json({ success: true, monitors });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// POST /api/monitors/stop/:pid - Stop a monitor
app.post('/api/monitors/stop/:pid', async (req: Request, res: Response) => {
  try {
    const pid = parseInt(req.params.pid);
    await execAsync(`kill ${pid}`);
    res.json({ success: true, message: `Monitor with PID ${pid} stopped` });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// GET /api/prs - Get all tracked PRs
app.get('/api/prs', async (req: Request, res: Response) => {
  try {
    const prs = await db.all(`
      SELECT
        p.*,
        COUNT(DISTINCT c.id) as comment_count,
        COUNT(DISTINCT w.id) as workflow_count,
        SUM(CASE WHEN w.conclusion = 'failure' THEN 1 ELSE 0 END) as failed_workflow_count,
        SUM(CASE WHEN c.addressed = 0 THEN 1 ELSE 0 END) as unaddressed_comment_count
      FROM prs p
      LEFT JOIN comments c ON c.pr_id = p.id
      LEFT JOIN workflows w ON w.pr_id = p.id
      GROUP BY p.id
      ORDER BY p.updated_at DESC
    `);

    res.json({ success: true, prs });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// GET /api/prs/:prNumber - Get PR details
app.get('/api/prs/:prNumber', (req: Request, res: Response) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string | undefined;

    let query = 'SELECT * FROM prs WHERE pr_number = ?';
    const params: any[] = [prNumber];

    if (repo) {
      query += ' AND repo = ?';
      params.push(repo);
    }

    const pr = db.prepare(query).get(...params) as PRData | undefined;

    if (!pr) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    res.json({ success: true, pr });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// GET /api/prs/:prNumber/comments - Get PR comments
app.get('/api/prs/:prNumber/comments', (req: Request, res: Response) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string | undefined;

    // Get PR ID first
    let prQuery = 'SELECT id FROM prs WHERE pr_number = ?';
    const prParams: any[] = [prNumber];

    if (repo) {
      prQuery += ' AND repo = ?';
      prParams.push(repo);
    }

    const pr = db.prepare(prQuery).get(...prParams) as { id: number } | undefined;

    if (!pr) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    const comments = db.prepare(`
      SELECT * FROM comments
      WHERE pr_id = ?
      ORDER BY created_at DESC
    `).all(pr.id) as Comment[];

    res.json({ success: true, comments });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// GET /api/prs/:prNumber/workflows - Get PR workflows
app.get('/api/prs/:prNumber/workflows', (req: Request, res: Response) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string | undefined;

    // Get PR ID first
    let prQuery = 'SELECT id FROM prs WHERE pr_number = ?';
    const prParams: any[] = [prNumber];

    if (repo) {
      prQuery += ' AND repo = ?';
      prParams.push(repo);
    }

    const pr = db.prepare(prQuery).get(...prParams) as { id: number } | undefined;

    if (!pr) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    const workflows = db.prepare(`
      SELECT * FROM workflows
      WHERE pr_id = ?
      ORDER BY created_at DESC
    `).all(pr.id) as Workflow[];

    res.json({ success: true, workflows });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// GET /api/prs/:prNumber/activities - Get PR activities
app.get('/api/prs/:prNumber/activities', (req: Request, res: Response) => {
  try {
    const prNumber = parseInt(req.params.prNumber);
    const repo = req.query.repo as string | undefined;

    // Get PR ID first
    let prQuery = 'SELECT id FROM prs WHERE pr_number = ?';
    const prParams: any[] = [prNumber];

    if (repo) {
      prQuery += ' AND repo = ?';
      prParams.push(repo);
    }

    const pr = db.prepare(prQuery).get(...prParams) as { id: number } | undefined;

    if (!pr) {
      return res.status(404).json({ success: false, error: 'PR not found' });
    }

    const activities = db.prepare(`
      SELECT * FROM activities
      WHERE pr_id = ?
      ORDER BY activity_time DESC
      LIMIT 100
    `).all(pr.id) as Activity[];

    res.json({ success: true, activities });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// POST /api/comments/:commentId/address - Mark comment as addressed
app.post('/api/comments/:commentId/address', (req: Request, res: Response) => {
  try {
    const commentId = parseInt(req.params.commentId);
    const { notes } = req.body;

    const result = db.prepare(`
      UPDATE comments
      SET addressed = 1,
          addressed_at = CURRENT_TIMESTAMP,
          addressed_notes = ?
      WHERE comment_id = ?
    `).run(notes || 'Marked as addressed via dashboard', commentId);

    if (result.changes === 0) {
      return res.status(404).json({ success: false, error: 'Comment not found' });
    }

    res.json({ success: true, message: 'Comment marked as addressed' });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// GET /api/stats - Get overall statistics
app.get('/api/stats', (req: Request, res: Response) => {
  try {
    const stats = {
      total_prs: db.prepare('SELECT COUNT(*) as count FROM prs').get() as { count: number },
      open_prs: db.prepare('SELECT COUNT(*) as count FROM prs WHERE state = "open"').get() as { count: number },
      total_comments: db.prepare('SELECT COUNT(*) as count FROM comments').get() as { count: number },
      unaddressed_comments: db.prepare('SELECT COUNT(*) as count FROM comments WHERE addressed = 0').get() as { count: number },
      total_workflows: db.prepare('SELECT COUNT(*) as count FROM workflows').get() as { count: number },
      failed_workflows: db.prepare('SELECT COUNT(*) as count FROM workflows WHERE conclusion = "failure"').get() as { count: number }
    };

    res.json({ success: true, stats });
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// Serve index.html for all other routes
app.get('*', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 PR Monitor Dashboard running at http://localhost:${PORT}`);
  console.log(`📊 Database: ${DB_PATH}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  db.close();
  process.exit(0);
});
