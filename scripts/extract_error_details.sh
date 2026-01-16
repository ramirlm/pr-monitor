#!/usr/bin/env bash
#
# extract_error_details.sh
# Extract detailed error messages from failed GitHub Actions jobs
#
# Usage:
#   ./extract_error_details.sh <RUN_ID>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_env

RUN_ID="${1:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || echo '')}"
GITHUB_REPO="${GITHUB_REPO:-}"

if [[ -z "${RUN_ID}" ]]; then
    echo "Usage: $0 <RUN_ID>"
    exit 1
fi

if [[ -z "${GITHUB_TOKEN}" ]]; then
    echo "ERROR: GITHUB_TOKEN not set"
    exit 1
fi

if [[ -z "${GITHUB_REPO}" ]]; then
    echo "ERROR: GITHUB_REPO not set"
    exit 1
fi

echo "Fetching detailed errors for workflow run ${RUN_ID}..."
echo ""

# Get all jobs for this run
JOBS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runs/${RUN_ID}/jobs")

# Extract failed jobs
FAILED_JOBS=$(echo "${JOBS}" | jq -r '.jobs[] | select(.conclusion == "failure")')

if [[ -z "${FAILED_JOBS}" ]] || [[ "${FAILED_JOBS}" == "null" ]]; then
    echo "✅ No failed jobs found in this workflow run"
    exit 0
fi

echo "${FAILED_JOBS}" | jq -c '.' | while read -r job; do
    JOB_ID=$(echo "${job}" | jq -r '.id')
    JOB_NAME=$(echo "${job}" | jq -r '.name')
    JOB_URL=$(echo "${job}" | jq -r '.html_url')

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ Job: ${JOB_NAME}"
    echo "🔗 URL: ${JOB_URL}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get failed steps with their actual output
    echo "${job}" | jq -r '.steps[] | select(.conclusion == "failure") |
        "Step: \(.name)\n" +
        "Status: \(.conclusion)\n" +
        "Started: \(.started_at // "N/A")\n" +
        "Completed: \(.completed_at // "N/A")\n" +
        "---"'

    echo ""

    # Extract error patterns from step names and conclusions
    ERRORS=$(echo "${job}" | jq -r '.steps[] | select(.conclusion == "failure") | .name')

    if [[ -n "${ERRORS}" ]]; then
        echo "📋 Failed Steps Summary:"
        echo "${ERRORS}" | sed 's/^/  • /'
        echo ""
    fi

    echo ""
done

# Create a JSON summary for programmatic use
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 JSON Summary (for parsing):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "${FAILED_JOBS}" | jq -c '{
    job_id: .id,
    job_name: .name,
    conclusion: .conclusion,
    html_url: .html_url,
    runner_name: .runner_name,
    failed_steps: [.steps[] | select(.conclusion == "failure") | {
        name: .name,
        number: .number,
        started_at: .started_at,
        completed_at: .completed_at,
        conclusion: .conclusion
    }]
}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
