#!/usr/bin/env bash
#
# init_pr_db.sh
# Initialize SQLite database for PR monitoring
#
# Usage:
#   ./init_pr_db.sh [DB_PATH]
#
# Default DB path: ~/.pr_monitor/pr_tracking.db

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_env

# Get repository root
REPO_ROOT=$(get_repo_root)

# Use provided path or default to repository-local database
DB_PATH="${1:-${REPO_ROOT}/.pr_monitor/data/pr_tracking.db}"
DB_DIR=$(dirname "${DB_PATH}")

# Create directory if it doesn't exist
mkdir -p "${DB_DIR}"

echo "Initializing PR tracking database at: ${DB_PATH}"

# Create database and tables
sqlite3 "${DB_PATH}" <<'EOF'
-- PRs table: Store PR metadata
CREATE TABLE IF NOT EXISTS prs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_number INTEGER NOT NULL,
    repo TEXT NOT NULL,
    title TEXT,
    state TEXT NOT NULL, -- open, closed, merged
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP,
    author TEXT,
    url TEXT,
    UNIQUE(pr_number, repo)
);

-- Comments table: Track all comments
CREATE TABLE IF NOT EXISTS comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_id INTEGER NOT NULL,
    comment_id INTEGER NOT NULL, -- GitHub comment ID
    comment_type TEXT NOT NULL, -- review, issue
    author TEXT NOT NULL,
    body TEXT NOT NULL,
    file_path TEXT, -- for review comments
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notified_at TIMESTAMP,
    addressed BOOLEAN DEFAULT 0, -- whether comment was addressed
    addressed_at TIMESTAMP,
    addressed_notes TEXT,
    FOREIGN KEY (pr_id) REFERENCES prs(id),
    UNIQUE(comment_id, pr_id)
);

-- Workflows table: Track workflow runs
CREATE TABLE IF NOT EXISTS workflows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL, -- GitHub workflow run ID
    workflow_name TEXT NOT NULL,
    status TEXT NOT NULL, -- queued, in_progress, completed
    conclusion TEXT, -- success, failure, cancelled, skipped
    head_sha TEXT, -- Commit SHA for this run
    html_url TEXT, -- URL to view the workflow run
    run_number INTEGER, -- Workflow run number
    run_attempt INTEGER, -- Attempt number for reruns
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    notified_at TIMESTAMP,
    failure_details TEXT, -- JSON with failed jobs/steps
    FOREIGN KEY (pr_id) REFERENCES prs(id),
    UNIQUE(run_id, pr_id)
);

-- Workflow jobs table: Track individual jobs within workflows
CREATE TABLE IF NOT EXISTS workflow_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_id INTEGER NOT NULL,
    pr_id INTEGER NOT NULL,
    job_id INTEGER NOT NULL, -- GitHub job ID
    job_name TEXT NOT NULL,
    status TEXT NOT NULL, -- queued, in_progress, completed
    conclusion TEXT, -- success, failure, cancelled, skipped
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    html_url TEXT, -- URL to view the job logs
    runner_name TEXT, -- Runner that executed the job
    failed_steps TEXT, -- JSON array of failed step names
    error_message TEXT, -- First error message from failed steps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (workflow_id) REFERENCES workflows(id),
    FOREIGN KEY (pr_id) REFERENCES prs(id),
    UNIQUE(job_id, workflow_id)
);

-- Check history: Log each monitoring iteration
CREATE TABLE IF NOT EXISTS check_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_id INTEGER NOT NULL,
    check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    pr_state TEXT NOT NULL,
    comment_count INTEGER DEFAULT 0,
    workflow_count INTEGER DEFAULT 0,
    failed_workflows INTEGER DEFAULT 0,
    notes TEXT,
    FOREIGN KEY (pr_id) REFERENCES prs(id)
);

-- Activities table: Log what was worked on
CREATE TABLE IF NOT EXISTS activities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_id INTEGER NOT NULL,
    activity_type TEXT NOT NULL, -- comment_posted, workflow_failed, workflow_passed, pr_updated, work_logged
    activity_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    summary TEXT NOT NULL,
    details TEXT, -- JSON or text details
    actor TEXT, -- who did it (user, bot, system)
    FOREIGN KEY (pr_id) REFERENCES prs(id)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_prs_repo ON prs(repo);
CREATE INDEX IF NOT EXISTS idx_prs_state ON prs(state);
CREATE INDEX IF NOT EXISTS idx_comments_pr ON comments(pr_id);
CREATE INDEX IF NOT EXISTS idx_comments_addressed ON comments(addressed);
CREATE INDEX IF NOT EXISTS idx_workflows_pr ON workflows(pr_id);
CREATE INDEX IF NOT EXISTS idx_workflows_status ON workflows(status, conclusion);
CREATE INDEX IF NOT EXISTS idx_workflow_jobs_workflow ON workflow_jobs(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_jobs_pr ON workflow_jobs(pr_id);
CREATE INDEX IF NOT EXISTS idx_workflow_jobs_status ON workflow_jobs(status, conclusion);
CREATE INDEX IF NOT EXISTS idx_check_history_pr ON check_history(pr_id);
CREATE INDEX IF NOT EXISTS idx_activities_pr ON activities(pr_id);
CREATE INDEX IF NOT EXISTS idx_activities_type ON activities(activity_type);

EOF

echo "✅ Database initialized successfully!"
echo ""
echo "Database location: ${DB_PATH}"
echo ""
echo "Tables created:"
echo "  - prs: PR metadata"
echo "  - comments: All comments with addressed status"
echo "  - workflows: Workflow runs and failures"
echo "  - workflow_jobs: Individual jobs within workflows"
echo "  - check_history: Monitoring check logs"
echo "  - activities: Work activity log"
echo ""
echo "To query the database:"
echo "  sqlite3 ${DB_PATH}"
