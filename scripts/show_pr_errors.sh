#!/usr/bin/env bash
#
# show_pr_errors.sh
# Show all errors for a PR with detailed, actionable information
#
# Usage:
#   ./show_pr_errors.sh <PR_NUMBER>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_env

REPO_ROOT=$(get_repo_root)
DB_PATH="${REPO_ROOT}/.pr_monitor/data/pr_tracking.db"
PR_NUMBER="${1:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || echo '')}"
GITHUB_REPO="${GITHUB_REPO:-}"

if [[ -z "${PR_NUMBER}" ]]; then
    echo "Usage: $0 <PR_NUMBER>"
    exit 1
fi

if [[ ! -f "${DB_PATH}" ]]; then
    echo "ERROR: Database not found at ${DB_PATH}"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 FAILED ACTIONS FOR PR #${PR_NUMBER}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get PR ID
PR_ID=$(sqlite3 "${DB_PATH}" "SELECT id FROM prs WHERE pr_number = ${PR_NUMBER};" 2>/dev/null)

if [[ -z "${PR_ID}" ]]; then
    echo "❌ PR #${PR_NUMBER} not found in database"
    echo "Tip: Start monitoring this PR first: ./pr-monitor.sh start ${PR_NUMBER}"
    exit 1
fi

# Get count of failed jobs
FAILED_COUNT=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM workflow_jobs WHERE pr_id = ${PR_ID} AND conclusion = 'failure';")

if [[ "${FAILED_COUNT}" -eq 0 ]]; then
    echo "✅ No failed jobs found for PR #${PR_NUMBER}"
    echo ""

    # Show summary of all workflows
    echo "📊 Workflow Summary:"
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    COUNT(DISTINCT w.id) as total_workflows,
    SUM(CASE WHEN w.conclusion = 'success' THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN w.status != 'completed' THEN 1 ELSE 0 END) as running
FROM workflows w
WHERE w.pr_id = ${PR_ID};
EOF
    exit 0
fi

echo "Found ${FAILED_COUNT} failed job(s)"
echo ""

# Get detailed information about failed jobs
FAILED_JOBS=$(sqlite3 -json "${DB_PATH}" <<EOF
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
    w.head_sha
FROM workflow_jobs j
JOIN workflows w ON w.id = j.workflow_id
WHERE j.pr_id = ${PR_ID} AND j.conclusion = 'failure'
ORDER BY j.completed_at DESC;
EOF
)

# Process each failed job
echo "${FAILED_JOBS}" | jq -c '.[]' | while read -r job; do
    WORKFLOW_NAME=$(echo "${job}" | jq -r '.workflow_name')
    JOB_NAME=$(echo "${job}" | jq -r '.job_name')
    JOB_URL=$(echo "${job}" | jq -r '.job_url')
    FAILED_STEPS=$(echo "${job}" | jq -r '.failed_steps // "[]"')
    ERROR_MSG=$(echo "${job}" | jq -r '.error_message // "Unknown error"')
    RUN_ID=$(echo "${job}" | jq -r '.run_id')
    RUNNER=$(echo "${job}" | jq -r '.runner_name // "Unknown"')
    COMPLETED=$(echo "${job}" | jq -r '.completed_at // "Unknown"')

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ Workflow: ${WORKFLOW_NAME}"
    echo "   Job: ${JOB_NAME}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🔗 Job URL: ${JOB_URL}"
    echo "🏃 Runner: ${RUNNER}"
    echo "⏱️  Completed: ${COMPLETED}"
    echo ""

    # Parse and display failed steps
    if [[ "${FAILED_STEPS}" != "[]" ]] && [[ "${FAILED_STEPS}" != "null" ]]; then
        echo "📋 Failed Steps:"
        echo "${FAILED_STEPS}" | jq -r '.[]' 2>/dev/null | while read -r step; do
            echo "   • ${step}"
        done
    else
        echo "📋 Primary Error: ${ERROR_MSG}"
    fi
    echo ""

    # Fetch detailed error from GitHub API if available
    if [[ -n "${GITHUB_TOKEN}" ]] && [[ -n "${RUN_ID}" ]]; then
        echo "🔍 Fetching detailed error information from GitHub..."

        # Get job details from API
        JOB_DETAILS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/actions/runs/${RUN_ID}/jobs" | \
            jq ".jobs[] | select(.name == \"${JOB_NAME}\")")

        if [[ -n "${JOB_DETAILS}" ]]; then
            # Extract failed step details
            echo ""
            echo "📝 Detailed Step Information:"
            echo "${JOB_DETAILS}" | jq -r '.steps[] | select(.conclusion == "failure") |
                "\n  Step: \(.name)\n  Number: \(.number)\n  Started: \(.started_at // "N/A")\n  Completed: \(.completed_at // "N/A")\n  Duration: \(if .started_at and .completed_at then
                    ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))
                else "N/A" end)s"'
            echo ""
        fi
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
done

# Show summary and actionable items
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total Failed Jobs: ${FAILED_COUNT}"
echo ""

# Group failures by workflow
echo "Failures by Workflow:"
sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    w.workflow_name,
    COUNT(j.id) as failed_jobs,
    GROUP_CONCAT(j.job_name, ', ') as jobs
FROM workflow_jobs j
JOIN workflows w ON w.id = j.workflow_id
WHERE j.pr_id = ${PR_ID} AND j.conclusion = 'failure'
GROUP BY w.workflow_name;
EOF
echo ""

# Generate actionable JSON for programmatic use
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 ACTIONABLE JSON OUTPUT (for AI agent)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "${FAILED_JOBS}" | jq '{
    pr_number: '"${PR_NUMBER}"',
    total_failures: (. | length),
    failed_jobs: [.[] | {
        workflow: .workflow_name,
        job: .job_name,
        error: .error_message,
        failed_steps: (.failed_steps | if type == "string" then (. | fromjson) else . end),
        job_url: .job_url,
        runner: .runner_name,
        completed_at: .completed_at
    }]
}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Next Steps:"
echo "   1. Review the failed job logs at the URLs above"
echo "   2. Use the JSON output to feed into an AI agent for automated fixes"
echo "   3. Re-run failed jobs after fixes: gh workflow run <workflow-name>"
echo ""
