# Enhanced Workflow Tracking

The PR Monitor now includes comprehensive GitHub Actions workflow and job tracking. Every time the monitor checks a PR, it fetches detailed information about all workflows and their individual jobs, storing everything in the database for analysis.

## What Gets Tracked

### Workflow Information
For each GitHub Actions workflow run, we track:
- **Basic Info**: Workflow name, run ID, run number, attempt number
- **Status**: queued, in_progress, or completed
- **Conclusion**: success, failure, cancelled, or skipped
- **Links**: Direct URL to view the workflow on GitHub
- **Commit**: SHA of the commit that triggered the workflow

### Job Information (NEW!)
For each job within a workflow, we track:
- **Job Details**: Job ID, name, status, conclusion
- **Execution**: Start time, completion time, runner name
- **Failures**: List of failed steps, first error message
- **Links**: Direct URL to view job logs on GitHub

## Database Schema

### Tables

**workflows** - Stores workflow run information
```sql
- id, pr_id, run_id (GitHub workflow run ID)
- workflow_name, status, conclusion
- head_sha, html_url, run_number, run_attempt
- created_at, started_at, completed_at
- failure_details
```

**workflow_jobs** - Stores individual job information
```sql
- id, workflow_id, pr_id, job_id (GitHub job ID)
- job_name, status, conclusion
- started_at, completed_at
- html_url, runner_name
- failed_steps (JSON array), error_message
```

## How It Works

When the monitor runs (every CHECK_INTERVAL seconds):

1. **Fetch Workflows**: Gets all workflow runs for the PR's HEAD commit
2. **Fetch Jobs**: For each workflow, fetches all jobs with their detailed status
3. **Extract Failures**: For failed jobs, extracts which steps failed and error messages
4. **Store Everything**: Saves all workflow and job data to SQLite database
5. **Notify on Failures**: Sends notifications for new failures with AI analysis

## API Endpoints

### Get All Workflows with Job Counts
```bash
GET /api/prs/:prNumber/workflows
```
Returns all workflows for a PR with aggregated job statistics.

**Response:**
```json
{
  "success": true,
  "workflows": [
    {
      "id": 1,
      "workflow_name": "CI",
      "status": "completed",
      "conclusion": "failure",
      "job_count": 5,
      "failed_job_count": 1,
      "successful_job_count": 4,
      "in_progress_job_count": 0,
      "html_url": "https://github.com/..."
    }
  ]
}
```

### Get Jobs for Specific Workflow
```bash
GET /api/workflows/:workflowId/jobs
```
Returns all jobs for a specific workflow, sorted by failure status.

**Response:**
```json
{
  "success": true,
  "jobs": [
    {
      "id": 1,
      "job_id": 123456,
      "job_name": "test-unit",
      "status": "completed",
      "conclusion": "failure",
      "failed_steps": "[\"Run tests\", \"Upload coverage\"]",
      "error_message": "Run tests",
      "html_url": "https://github.com/.../123456",
      "runner_name": "GitHub Actions 2"
    }
  ]
}
```

### Get All Failed Jobs
```bash
GET /api/prs/:prNumber/failed-jobs
```
Returns all failed jobs across all workflows for a PR with workflow context.

**Response:**
```json
{
  "success": true,
  "failed_jobs": [
    {
      "job_id": 123456,
      "job_name": "test-unit",
      "workflow_name": "CI",
      "run_number": 42,
      "failed_steps": "[\"Run tests\"]",
      "error_message": "Run tests",
      "html_url": "https://github.com/.../123456",
      "workflow_url": "https://github.com/..."
    }
  ]
}
```

### Get Workflow Summary
```bash
GET /api/prs/:prNumber/workflow-summary
```
Returns aggregated statistics for all workflows and jobs.

**Response:**
```json
{
  "success": true,
  "summary": {
    "workflows": {
      "total_workflows": 5,
      "successful_workflows": 4,
      "failed_workflows": 1,
      "in_progress_workflows": 0,
      "queued_workflows": 0
    },
    "jobs": {
      "total_jobs": 25,
      "successful_jobs": 23,
      "failed_jobs": 2,
      "in_progress_jobs": 0
    }
  }
}
```

## Testing

### Test Script
Run the test script to see workflow data for any PR:

```bash
# Auto-detect PR from current branch
./test-workflow-tracking.sh

# Specific PR number
./test-workflow-tracking.sh 4492
```

### Manual Database Queries

Get workflow summary:
```bash
sqlite3 data/pr_tracking.db "
SELECT
    w.workflow_name,
    w.status,
    w.conclusion,
    COUNT(j.id) as total_jobs,
    SUM(CASE WHEN j.conclusion = 'failure' THEN 1 ELSE 0 END) as failed_jobs
FROM workflows w
LEFT JOIN workflow_jobs j ON j.workflow_id = w.id
JOIN prs p ON p.id = w.pr_id
WHERE p.pr_number = 4492
GROUP BY w.id;
"
```

Get failed jobs with details:
```bash
sqlite3 data/pr_tracking.db "
SELECT
    w.workflow_name,
    j.job_name,
    j.failed_steps,
    j.html_url
FROM workflow_jobs j
JOIN workflows w ON w.id = j.workflow_id
JOIN prs p ON p.id = j.pr_id
WHERE p.pr_number = 4492 AND j.conclusion = 'failure';
"
```

## Usage Example

### 1. Start Monitoring
```bash
./pr-monitor.sh start 4492
```

### 2. Monitor Runs and Collects Data
The monitor will:
- Check workflows every CHECK_INTERVAL seconds (default: 60)
- Store workflow and job information
- Send notifications for new failures
- Include AI analysis of failures

### 3. Query the Data

**Via Test Script:**
```bash
./test-workflow-tracking.sh 4492
```

**Via API:**
```bash
# Get workflow summary
curl http://localhost:3000/api/prs/4492/workflow-summary

# Get failed jobs
curl http://localhost:3000/api/prs/4492/failed-jobs

# Get all workflows
curl http://localhost:3000/api/prs/4492/workflows
```

**Via Dashboard:**
Visit http://localhost:3000 and navigate to the PR details page.

## Benefits

1. **Complete Visibility**: See not just which workflows failed, but which specific jobs and steps
2. **Historical Tracking**: All workflow runs are stored, so you can see trends over time
3. **Quick Debugging**: Failed steps are identified immediately with direct links to logs
4. **AI Analysis**: Claude analyzes failures in context of PR changes
5. **Efficient Queries**: Indexed database allows fast queries across all PRs

## Migration Notes

- Existing workflows in the database won't have job data until the monitor runs again
- New workflow runs will automatically have full job tracking
- The database schema is backward compatible (old code continues to work)
- Job tracking adds minimal overhead (one additional API call per workflow)

## Troubleshooting

**No job data showing?**
- The monitor needs to run at least once after the upgrade
- Stop and restart the monitor: `./pr-monitor.sh stop 4492 && ./pr-monitor.sh start 4492`

**"No such column" errors?**
- Run database migration: `./pr-monitor.sh init`
- This will add new columns and tables without losing existing data

**High API usage?**
- Each workflow requires one additional API call to fetch jobs
- GitHub API limit: 5000 requests/hour for authenticated users
- Default CHECK_INTERVAL (60s) = 60 checks/hour, well within limits
