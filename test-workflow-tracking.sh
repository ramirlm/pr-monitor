#!/usr/bin/env bash
#
# Test script to demonstrate enhanced workflow tracking
# This script queries the database to show all workflow and job information

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${SCRIPT_DIR}/data/pr_tracking.db"

echo "======================================"
echo "Enhanced Workflow Tracking Test"
echo "======================================"
echo ""

# Check if database exists
if [[ ! -f "${DB_PATH}" ]]; then
    echo "❌ Database not found at ${DB_PATH}"
    echo "Please run: ./pr-monitor.sh init"
    exit 1
fi

# Get PR number from argument or detect from current branch
PR_NUM="${1:-}"
if [[ -z "${PR_NUM}" ]]; then
    PR_NUM=$(gh pr list --head "$(git branch --show-current)" --json number --jq '.[0].number' 2>/dev/null || echo "")
fi

if [[ -z "${PR_NUM}" ]]; then
    echo "❌ No PR number provided and could not detect from current branch"
    echo "Usage: $0 <PR_NUMBER>"
    exit 1
fi

echo "📊 Querying data for PR #${PR_NUM}"
echo ""

# Get PR info
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 PR Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT pr_number, repo, title, state, author
FROM prs
WHERE pr_number = ${PR_NUM};
EOF
echo ""

# Get workflow summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 Workflow Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    COUNT(*) as total_workflows,
    SUM(CASE WHEN conclusion = 'success' THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN conclusion = 'failure' THEN 1 ELSE 0 END) as failed,
    SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress,
    SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) as queued
FROM workflows w
JOIN prs p ON p.id = w.pr_id
WHERE p.pr_number = ${PR_NUM};
EOF
echo ""

# Get job summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Job Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    COUNT(*) as total_jobs,
    SUM(CASE WHEN conclusion = 'success' THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN conclusion = 'failure' THEN 1 ELSE 0 END) as failed,
    SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress
FROM workflow_jobs j
JOIN prs p ON p.id = j.pr_id
WHERE p.pr_number = ${PR_NUM};
EOF
echo ""

# Get all workflows with job counts
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚙️  All Workflows (with job counts)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    w.workflow_name,
    w.status,
    w.conclusion,
    COUNT(j.id) as total_jobs,
    SUM(CASE WHEN j.conclusion = 'failure' THEN 1 ELSE 0 END) as failed_jobs,
    SUM(CASE WHEN j.conclusion = 'success' THEN 1 ELSE 0 END) as passed_jobs
FROM workflows w
LEFT JOIN workflow_jobs j ON j.workflow_id = w.id
JOIN prs p ON p.id = w.pr_id
WHERE p.pr_number = ${PR_NUM}
GROUP BY w.id
ORDER BY w.created_at DESC
LIMIT 10;
EOF
echo ""

# Get failed jobs (if any)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "❌ Failed Jobs (detailed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
FAILED_COUNT=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM workflow_jobs j JOIN prs p ON p.id = j.pr_id WHERE p.pr_number = ${PR_NUM} AND j.conclusion = 'failure';")

if [[ "${FAILED_COUNT}" -eq 0 ]]; then
    echo "✅ No failed jobs found!"
else
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    w.workflow_name,
    j.job_name,
    j.conclusion,
    j.failed_steps,
    j.error_message,
    j.html_url
FROM workflow_jobs j
JOIN workflows w ON w.id = j.workflow_id
JOIN prs p ON p.id = j.pr_id
WHERE p.pr_number = ${PR_NUM} AND j.conclusion = 'failure'
ORDER BY j.completed_at DESC
LIMIT 20;
EOF
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Enhanced tracking is working!"
echo ""
echo "Available API endpoints:"
echo "  GET /api/prs/${PR_NUM}/workflows          - All workflows with job counts"
echo "  GET /api/workflows/:workflowId/jobs       - Jobs for a specific workflow"
echo "  GET /api/prs/${PR_NUM}/failed-jobs        - All failed jobs with details"
echo "  GET /api/prs/${PR_NUM}/workflow-summary   - Summary statistics"
echo ""
echo "To view in dashboard: http://localhost:3000"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
