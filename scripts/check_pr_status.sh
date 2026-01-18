#!/usr/bin/env bash
#
# check_pr_status.sh
# Monitor GitHub PR status, actions, and comments every 15 minutes
# Integrates with Claude code -p for AI analysis and Pushover for notifications
#
# Usage:
#   ./check_pr_status.sh <PR_NUMBER> [REPO]
#
# Arguments:
#   PR_NUMBER          - Required. The PR number to monitor
#   REPO               - Optional. Repository in format "owner/repo" (overrides GITHUB_REPO env var)
#
# Environment Variables:
#   GITHUB_TOKEN       - Required. GitHub personal access token (or uses 'gh auth token')
#   GITHUB_REPO        - Optional. Repository in format "owner/repo" (can be overridden by REPO argument)
#   PUSHOVER_USER      - Required. Pushover user key
#   PUSHOVER_TOKEN     - Required. Pushover API token
#   CHECK_INTERVAL     - Optional. Check interval in seconds (default: 900 = 15 minutes)
#   STATE_FILE         - Optional. File to store state (default: /tmp/pr_monitor_state_<PR>.json)

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_env

# Get repository root
REPO_ROOT=$(get_repo_root)

# Configuration
PR_NUMBER="${1:-}"
REPO_ARG="${2:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-900}"  # 15 minutes
# Use provided token, env var, or fall back to gh auth token
GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || echo '')}"
# Use repo argument if provided, otherwise fall back to env var
GITHUB_REPO="${REPO_ARG:-${GITHUB_REPO:-}}"
PUSHOVER_USER="${PUSHOVER_USER:-}"
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"
STATE_FILE="${STATE_FILE:-${REPO_ROOT}/.pr_monitor/data/state/pr_${PR_NUMBER}.json}"
LOG_FILE="${LOG_FILE:-${REPO_ROOT}/.pr_monitor/logs/pr_${PR_NUMBER}.log}"
DB_PATH="${DB_PATH:-${REPO_ROOT}/.pr_monitor/data/pr_tracking.db}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 <PR_NUMBER> [REPO]

Monitor GitHub PR status, actions, and comments every 15 minutes.
Sends notifications via Pushover and uses Claude for AI analysis.

Arguments:
  PR_NUMBER          The PR number to monitor (required)
  REPO               Repository in format "owner/repo" (optional, overrides GITHUB_REPO)

Environment Variables:
  GITHUB_TOKEN       GitHub personal access token (auto-detected from 'gh auth token' if not set)
  GITHUB_REPO        Repository in format "owner/repo" (can be overridden by REPO argument)
  PUSHOVER_USER      Pushover user key (required)
  PUSHOVER_TOKEN     Pushover API token (required)
  CHECK_INTERVAL     Check interval in seconds (default: 900)
  STATE_FILE         File to store state (default: /tmp/pr_monitor_state_<PR>.json)

Examples:
  # Using repo argument (recommended for flexibility)
  $0 123 owner/repo

  # Using environment variables
  export GITHUB_REPO="owner/repo"
  export PUSHOVER_USER="xxxxx"
  export PUSHOVER_TOKEN="xxxxx"
  $0 123
EOF
    exit 1
}

# Validate inputs
validate_inputs() {
    if [[ -z "${PR_NUMBER}" ]]; then
        log "ERROR" "${RED}PR number is required${NC}"
        usage
    fi

    if [[ ! "${PR_NUMBER}" =~ ^[0-9]+$ ]]; then
        log "ERROR" "${RED}PR number must be a valid integer${NC}"
        exit 1
    fi

    if [[ -z "${GITHUB_TOKEN}" ]]; then
        log "ERROR" "${RED}GITHUB_TOKEN environment variable is required${NC}"
        exit 1
    fi

    if [[ -z "${GITHUB_REPO}" ]]; then
        log "ERROR" "${RED}GITHUB_REPO environment variable is required (format: owner/repo)${NC}"
        exit 1
    fi

    # Pushover notifications are optional
    if [[ -z "${PUSHOVER_USER}" ]] || [[ -z "${PUSHOVER_TOKEN}" ]]; then
        log "WARN" "${YELLOW}Pushover notifications disabled (PUSHOVER_USER or PUSHOVER_TOKEN not set)${NC}"
        PUSHOVER_ENABLED=false
    else
        PUSHOVER_ENABLED=true
    fi
}

# Send Pushover notification
send_pushover_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-0}"  # -2 to 2, default 0

    # Skip if Pushover is not enabled
    if [[ "${PUSHOVER_ENABLED}" != "true" ]]; then
        log "DEBUG" "Pushover disabled, skipping notification: ${title}"
        return 0
    fi

    log "INFO" "Sending Pushover notification: ${title}"

    local response
    response=$(curl -s -X POST https://api.pushover.net/1/messages.json \
        -d "token=${PUSHOVER_TOKEN}" \
        -d "user=${PUSHOVER_USER}" \
        -d "title=${title}" \
        -d "message=${message}" \
        -d "priority=${priority}" 2>&1)

    if echo "${response}" | grep -q '"status":1'; then
        log "INFO" "${GREEN}Pushover notification sent successfully${NC}"
        return 0
    else
        log "ERROR" "${RED}Failed to send Pushover notification: ${response}${NC}"
        return 1
    fi
}

# Database helper functions
# Initialize database and ensure PR record exists
db_init() {
    # Ensure database directory exists
    local db_dir=$(dirname "${DB_PATH}")
    mkdir -p "${db_dir}"

    # Check if database exists, if not, initialize it
    if [[ ! -f "${DB_PATH}" ]]; then
        log "INFO" "Database not found, initializing..."
        bash "$(dirname "$0")/init_pr_db.sh" "${DB_PATH}" > /dev/null 2>&1 || {
            log "WARN" "${YELLOW}Failed to initialize database, some features may not work${NC}"
            return 1
        }
    fi

    # Ensure PR exists in database
    local pr_id
    pr_id=$(sqlite3 "${DB_PATH}" "SELECT id FROM prs WHERE pr_number=${PR_NUMBER} AND repo='${GITHUB_REPO}';" 2>/dev/null || echo "")

    if [[ -z "${pr_id}" ]]; then
        log "INFO" "Creating PR record in database..."
        sqlite3 "${DB_PATH}" <<EOF
INSERT OR IGNORE INTO prs (pr_number, repo, state, url)
VALUES (${PR_NUMBER}, '${GITHUB_REPO}', 'open', 'https://github.com/${GITHUB_REPO}/pull/${PR_NUMBER}');
EOF
    fi
}

# Get PR database ID
db_get_pr_id() {
    sqlite3 "${DB_PATH}" "SELECT id FROM prs WHERE pr_number=${PR_NUMBER} AND repo='${GITHUB_REPO}';" 2>/dev/null || echo ""
}

# Update PR metadata
db_update_pr() {
    local pr_details="$1"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    local title=$(echo "${pr_details}" | jq -r '.title' | sed "s/'/''/g")
    local state=$(echo "${pr_details}" | jq -r '.state')
    local author=$(echo "${pr_details}" | jq -r '.user.login')

    sqlite3 "${DB_PATH}" <<EOF
UPDATE prs SET
    title='${title}',
    state='${state}',
    author='${author}',
    updated_at=CURRENT_TIMESTAMP
WHERE id=${pr_id};
EOF
}

# Log a comment to database
db_log_comment() {
    local comment_id="$1"
    local comment_type="$2"  # review or issue
    local author="$3"
    local body="$4"
    local file_path="${5:-}"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    # Escape single quotes in text
    author=$(echo "${author}" | sed "s/'/''/g")
    body=$(echo "${body}" | sed "s/'/''/g")
    file_path=$(echo "${file_path}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
INSERT OR IGNORE INTO comments (pr_id, comment_id, comment_type, author, body, file_path, notified_at)
VALUES (${pr_id}, ${comment_id}, '${comment_type}', '${author}', '${body}', '${file_path}', CURRENT_TIMESTAMP);
EOF

    # Log activity
    db_log_activity "comment_posted" "Comment from ${author}" "${body:0:100}..." "${author}"
}

# Log workflow run to database with enhanced details
db_log_workflow() {
    local run_id="$1"
    local workflow_name="$2"
    local status="$3"
    local conclusion="${4:-}"
    local failure_details="${5:-}"
    local head_sha="${6:-}"
    local html_url="${7:-}"
    local run_number="${8:-0}"
    local run_attempt="${9:-1}"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    # Escape single quotes
    workflow_name=$(echo "${workflow_name}" | sed "s/'/''/g")
    failure_details=$(echo "${failure_details}" | sed "s/'/''/g")
    html_url=$(echo "${html_url}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
INSERT OR REPLACE INTO workflows (
    pr_id, run_id, workflow_name, status, conclusion,
    head_sha, html_url, run_number, run_attempt,
    failure_details, completed_at, notified_at
)
VALUES (
    ${pr_id},
    ${run_id},
    '${workflow_name}',
    '${status}',
    '${conclusion}',
    '${head_sha}',
    '${html_url}',
    ${run_number},
    ${run_attempt},
    '${failure_details}',
    $([ "${status}" = "completed" ] && echo "CURRENT_TIMESTAMP" || echo "NULL"),
    $([ ! -z "${failure_details}" ] && echo "CURRENT_TIMESTAMP" || echo "NULL")
);
EOF

    # Log activity if workflow failed
    if [[ "${conclusion}" == "failure" ]]; then
        db_log_activity "workflow_failed" "Workflow '${workflow_name}' failed" "${failure_details}" "system"
    elif [[ "${conclusion}" == "success" ]]; then
        db_log_activity "workflow_passed" "Workflow '${workflow_name}' passed" "" "system"
    fi
}

# Get workflow database ID
db_get_workflow_id() {
    local run_id="$1"
    local pr_id=$(db_get_pr_id)
    [[ -z "${pr_id}" ]] && return 1

    sqlite3 "${DB_PATH}" "SELECT id FROM workflows WHERE run_id=${run_id} AND pr_id=${pr_id};" 2>/dev/null || echo ""
}

# Log workflow job to database
db_log_workflow_job() {
    local run_id="$1"
    local job_id="$2"
    local job_name="$3"
    local status="$4"
    local conclusion="${5:-}"
    local html_url="${6:-}"
    local runner_name="${7:-}"
    local failed_steps="${8:-}"
    local error_message="${9:-}"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    local workflow_id=$(db_get_workflow_id "${run_id}")
    [[ -z "${workflow_id}" ]] && return 1

    # Escape single quotes
    job_name=$(echo "${job_name}" | sed "s/'/''/g")
    html_url=$(echo "${html_url}" | sed "s/'/''/g")
    runner_name=$(echo "${runner_name}" | sed "s/'/''/g")
    failed_steps=$(echo "${failed_steps}" | sed "s/'/''/g")
    error_message=$(echo "${error_message}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
INSERT OR REPLACE INTO workflow_jobs (
    workflow_id, pr_id, job_id, job_name, status, conclusion,
    html_url, runner_name, failed_steps, error_message,
    completed_at, updated_at
)
VALUES (
    ${workflow_id},
    ${pr_id},
    ${job_id},
    '${job_name}',
    '${status}',
    '${conclusion}',
    '${html_url}',
    '${runner_name}',
    '${failed_steps}',
    '${error_message}',
    $([ "${status}" = "completed" ] && echo "CURRENT_TIMESTAMP" || echo "NULL"),
    CURRENT_TIMESTAMP
);
EOF
}

# Log general activity
db_log_activity() {
    local activity_type="$1"
    local summary="$2"
    local details="${3:-}"
    local actor="${4:-system}"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    # Escape single quotes
    summary=$(echo "${summary}" | sed "s/'/''/g")
    details=$(echo "${details}" | sed "s/'/''/g")
    actor=$(echo "${actor}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
INSERT INTO activities (pr_id, activity_type, summary, details, actor)
VALUES (${pr_id}, '${activity_type}', '${summary}', '${details}', '${actor}');
EOF
}

# Log monitoring check
db_log_check() {
    local pr_state="$1"
    local comment_count="$2"
    local workflow_count="$3"
    local failed_workflows="$4"
    local notes="${5:-}"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    notes=$(echo "${notes}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
INSERT INTO check_history (pr_id, pr_state, comment_count, workflow_count, failed_workflows, notes)
VALUES (${pr_id}, '${pr_state}', ${comment_count}, ${workflow_count}, ${failed_workflows}, '${notes}');
EOF
}

# Mark comment as addressed
db_mark_comment_addressed() {
    local comment_id="$1"
    local notes="${2:-}"
    local pr_id=$(db_get_pr_id)

    [[ -z "${pr_id}" ]] && return 1

    notes=$(echo "${notes}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
UPDATE comments SET
    addressed=1,
    addressed_at=CURRENT_TIMESTAMP,
    addressed_notes='${notes}'
WHERE comment_id=${comment_id} AND pr_id=${pr_id};
EOF
}

# Get PR details
get_pr_details() {
    local pr_url="https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}"
    
    curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
         -H "Accept: application/vnd.github.v3+json" \
         "${pr_url}"
}

# Get PR diff
get_pr_diff() {
    local pr_url="https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}"
    
    curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
         -H "Accept: application/vnd.github.v3.diff" \
         "${pr_url}"
}

# Get PR comments
get_pr_comments() {
    local comments_url="https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/comments"
    local issue_comments_url="https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments"
    
    # Get both review comments and issue comments
    local review_comments
    review_comments=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
                           -H "Accept: application/vnd.github.v3+json" \
                           "${comments_url}")
    
    local issue_comments
    issue_comments=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
                          -H "Accept: application/vnd.github.v3+json" \
                          "${issue_comments_url}")
    
    # Combine both comment types
    echo "{\"review_comments\": ${review_comments}, \"issue_comments\": ${issue_comments}}"
}

# Get workflow runs for PR
get_workflow_runs() {
    local pr_details="$1"
    local head_sha
    head_sha=$(echo "${pr_details}" | jq -r '.head.sha')
    
    local runs_url="https://api.github.com/repos/${GITHUB_REPO}/actions/runs?head_sha=${head_sha}"
    
    curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
         -H "Accept: application/vnd.github.v3+json" \
         "${runs_url}"
}

# Get all workflow jobs details (not just failed ones)
get_workflow_jobs() {
    local run_id="$1"
    local jobs_url="https://api.github.com/repos/${GITHUB_REPO}/actions/runs/${run_id}/jobs"

    local jobs
    jobs=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "${jobs_url}")

    echo "${jobs}"
}

# Initialize state file
initialize_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        log "INFO" "Initializing state file: ${STATE_FILE}"
        echo '{
            "last_comment_count": 0,
            "last_workflow_status": {},
            "notified_comments": [],
            "notified_workflows": [],
            "pipeline_passed": false,
            "pipeline_status": "unknown",
            "pipeline_notification_sent": false
        }' > "${STATE_FILE}"
    fi
}

# Load state
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        cat "${STATE_FILE}"
    else
        echo '{}'
    fi
}

# Save state
save_state() {
    local state="$1"
    echo "${state}" > "${STATE_FILE}"
}

# Call Claude code for analysis
call_claude_analysis() {
    local context_type="$1"  # "comment", "failure", or "diff"
    local context_data="$2"
    local prompt="$3"
    
    log "INFO" "${BLUE}Calling Claude for ${context_type} analysis${NC}"
    
    # Check if Claude CLI is available
    if ! command -v claude &> /dev/null; then
        log "WARN" "${YELLOW}Claude CLI not available, skipping AI analysis${NC}"
        echo "Claude CLI not installed - analysis skipped"
        return 0
    fi
    
    log "INFO" "Running Claude analysis..."
    
    # Combine context and prompt for Claude
    local full_prompt="${context_data}\n\n${prompt}"
    
    # Run Claude in headless/programmatic mode
    # Try 'claude code -p' first (as specified in requirements), fall back to 'claude -p'
    local analysis_result
    if claude code -p --help &> /dev/null; then
        # claude code -p is available
        analysis_result=$(echo -e "${full_prompt}" | claude code -p 2>&1 || true)
    elif claude -p --help &> /dev/null; then
        # Fall back to claude -p
        analysis_result=$(echo -e "${full_prompt}" | claude -p 2>&1 || true)
    else
        # Try claude code without -p flag
        analysis_result=$(echo -e "${full_prompt}" | claude code 2>&1 || true)
    fi
    
    # Check if the result contains an error
    if echo "${analysis_result}" | grep -iq "error\|failed\|unauthorized"; then
        log "WARN" "${YELLOW}Claude analysis may have failed: ${analysis_result:0:100}...${NC}"
    fi
    
    echo "${analysis_result}"
}

# Process new comments
process_new_comments() {
    local current_comments="$1"
    local state="$2"
    
    local review_comments
    review_comments=$(echo "${current_comments}" | jq -r '.review_comments // [] | length')
    
    local issue_comments
    issue_comments=$(echo "${current_comments}" | jq -r '.issue_comments // [] | length')
    
    local total_comments=$((review_comments + issue_comments))
    
    local last_comment_count
    last_comment_count=$(echo "${state}" | jq -r '.last_comment_count // 0')
    
    if [[ ${total_comments} -gt ${last_comment_count} ]]; then
        log "INFO" "${GREEN}New comments detected: ${total_comments} (was ${last_comment_count})${NC}"
        
        # Process each review comment - avoid subshell by using process substitution
        # Use jq compact JSON for safe parsing
        while read -r comment_json; do
            [[ -z "${comment_json}" ]] && continue
            
            local id user body path
            id=$(echo "${comment_json}" | jq -r '.id')
            user=$(echo "${comment_json}" | jq -r '.user.login')
            body=$(echo "${comment_json}" | jq -r '.body')
            path=$(echo "${comment_json}" | jq -r '.path')
            
            local notified
            notified=$(echo "${state}" | jq -r ".notified_comments // [] | any(. == ${id})")
            
            if [[ "${notified}" == "false" ]]; then
                log "INFO" "Processing new review comment from ${user} on ${path}"
                
                # Get PR diff for context
                local pr_diff
                pr_diff=$(get_pr_diff)
                
                # Prepare context for Claude (safely escaped)
                local context="PR #${PR_NUMBER} - New Review Comment\n"
                context+="Author: ${user}\n"
                context+="File: ${path}\n"
                context+="Comment: ${body}\n\n"
                context+="PR Diff:\n${pr_diff}"
                
                # Call Claude for analysis
                local prompt="Analyze this PR review comment and provide insights on what changes might be needed. Be concise."
                local analysis
                analysis=$(call_claude_analysis "comment" "${context}" "${prompt}")
                
                # Send notification with properly escaped message
                # Use printf to safely format the message
                local notification_msg
                notification_msg=$(printf "New comment from %s on %s\n\n%s\n\nAI Analysis:\n%s" "${user}" "${path}" "${body}" "${analysis}")
                send_pushover_notification "PR #${PR_NUMBER}: New Comment" "${notification_msg}" 0

                # Log to database
                db_log_comment "${id}" "review" "${user}" "${body}" "${path}" 2>/dev/null || true

                # Update state
                state=$(echo "${state}" | jq ".notified_comments += [${id}]")
            fi
        done < <(echo "${current_comments}" | jq -c '.review_comments // [] | .[]')
        
        # Update comment count in state
        state=$(echo "${state}" | jq ".last_comment_count = ${total_comments}")
    fi
    
    echo "${state}"
}

# Process workflow runs with detailed job tracking
process_workflow_runs() {
    local workflow_runs="$1"
    local state="$2"
    local pr_details="$3"

    # Get PR title for notifications
    local pr_title
    pr_title=$(echo "${pr_details}" | jq -r '.title')

    local all_success=true
    local has_failures=false
    local all_completed=true
    local workflow_count=0

    # Process ALL workflows (not just completed ones) - avoid subshell by using process substitution
    while read -r run; do
        [[ -z "${run}" ]] && continue

        workflow_count=$((workflow_count + 1))
        local run_id run_name conclusion status head_sha html_url run_number run_attempt
        run_id=$(echo "${run}" | jq -r '.id')
        run_name=$(echo "${run}" | jq -r '.name')
        conclusion=$(echo "${run}" | jq -r '.conclusion // ""')
        status=$(echo "${run}" | jq -r '.status')
        head_sha=$(echo "${run}" | jq -r '.head_sha // ""')
        html_url=$(echo "${run}" | jq -r '.html_url // ""')
        run_number=$(echo "${run}" | jq -r '.run_number // 0')
        run_attempt=$(echo "${run}" | jq -r '.run_attempt // 1')

        log "INFO" "Workflow '${run_name}' (${run_id}): ${status} - ${conclusion}"

        # Check if workflow is still in progress
        if [[ "${status}" != "completed" ]]; then
            all_completed=false
            all_success=false
        fi

        # Get all jobs for this workflow (whether it's completed or not)
        local jobs
        jobs=$(get_workflow_jobs "${run_id}")

        # First, log the workflow itself to database with enhanced details
        db_log_workflow "${run_id}" "${run_name}" "${status}" "${conclusion}" "" "${head_sha}" "${html_url}" "${run_number}" "${run_attempt}" 2>/dev/null || true

        # Process all jobs for this workflow
        local job_count=0
        local failed_job_count=0
        local failed_jobs_summary=""

        while read -r job; do
            [[ -z "${job}" ]] && continue

            local job_id job_name job_status job_conclusion job_html_url runner_name
            job_id=$(echo "${job}" | jq -r '.id')
            job_name=$(echo "${job}" | jq -r '.name')
            job_status=$(echo "${job}" | jq -r '.status')
            job_conclusion=$(echo "${job}" | jq -r '.conclusion // ""')
            job_html_url=$(echo "${job}" | jq -r '.html_url // ""')
            runner_name=$(echo "${job}" | jq -r '.runner_name // ""')

            job_count=$((job_count + 1))

            # Extract failed steps and error messages
            local failed_steps=""
            local error_message=""

            if [[ "${job_conclusion}" == "failure" ]]; then
                failed_job_count=$((failed_job_count + 1))

                # Get failed steps with detailed error information as JSON
                failed_steps=$(echo "${job}" | jq -c '[.steps[] | select(.conclusion == "failure") | {
                    name: .name,
                    number: .number,
                    started_at: .started_at,
                    completed_at: .completed_at,
                    conclusion: .conclusion
                }]')

                # Extract just step names for summary
                local step_names
                step_names=$(echo "${failed_steps}" | jq -r '[.[].name] | join(", ")')

                # Get first failed step for primary error message
                error_message=$(echo "${failed_steps}" | jq -r '.[0].name // ""' 2>/dev/null || echo "")

                # Build summary for notification with step numbers
                failed_jobs_summary="${failed_jobs_summary}${job_name}:\n"
                echo "${failed_steps}" | jq -r '.[] | "  • Step \(.number): \(.name)"' | while read -r step_detail; do
                    failed_jobs_summary="${failed_jobs_summary}${step_detail}\n"
                done
                failed_jobs_summary="${failed_jobs_summary}\n"
            fi

            # Log job to database
            db_log_workflow_job "${run_id}" "${job_id}" "${job_name}" "${job_status}" "${job_conclusion}" "${job_html_url}" "${runner_name}" "${failed_steps}" "${error_message}" 2>/dev/null || true

        done < <(echo "${jobs}" | jq -c '.jobs[]?' 2>/dev/null || echo "")

        log "INFO" "  Jobs: ${job_count} total, ${failed_job_count} failed"

        # Check if this workflow failed and we haven't notified about it
        if [[ "${conclusion}" == "failure" ]]; then
            has_failures=true
            all_success=false

            local notified
            notified=$(echo "${state}" | jq -r ".notified_workflows // [] | any(. == ${run_id})")

            if [[ "${notified}" == "false" ]]; then
                log "ERROR" "${RED}Workflow '${run_name}' failed!${NC}"

                # Get PR diff for context
                local pr_diff
                pr_diff=$(get_pr_diff)

                # Prepare context for Claude (safely escaped)
                local context="PR #${PR_NUMBER} - Workflow Failure\n"
                context+="Workflow: ${run_name}\n"
                context+="Failed Jobs (${failed_job_count}/${job_count}):\n${failed_jobs_summary}\n\n"
                context+="Workflow URL: ${html_url}\n\n"
                context+="PR Diff:\n${pr_diff}"

                # Call Claude for analysis
                local prompt="Analyze this workflow failure in the context of the PR changes. Suggest what might be causing the failure and how to fix it. Be specific and concise."
                local analysis
                analysis=$(call_claude_analysis "failure" "${context}" "${prompt}")

                # Individual workflow failure notifications are disabled in favor of pipeline-level notifications
                # This prevents notification spam when multiple workflows fail
                # See PIPELINE_NOTIFICATIONS.md for details

                # Update state to mark this workflow as notified (for per-workflow tracking)
                state=$(echo "${state}" | jq ".notified_workflows += [${run_id}]")

                # ============================================================
                # AUTOMATED FIXING AGENT TRIGGER
                # ============================================================

                # Check if agent hasn't been triggered for this workflow yet
                local agent_triggered
                agent_triggered=$(echo "${state}" | jq -r ".agent_triggered_workflows // [] | any(. == ${run_id})")

                if [[ "${agent_triggered}" == "false" ]]; then
                    log "INFO" ""
                    log "INFO" "🤖 ${CYAN}=================================================${NC}"
                    log "INFO" "🤖 ${CYAN}AUTOMATED FIXING AGENT SYSTEM ACTIVATED${NC}"
                    log "INFO" "🤖 ${CYAN}=================================================${NC}"

                    # Classify failure type
                    local agent_type
                    agent_type=$(bash "${SCRIPT_DIR}/classify_failure.sh" "workflow_failure" "${failed_jobs_summary}" "${run_name}")

                    log "INFO" "🔍 Classified failure type: ${agent_type}"
                    local agent_desc
                    agent_desc=$(bash "${SCRIPT_DIR}/classify_failure.sh" "get_description" "${agent_type}")

                    # Prepare failure context for agent
                    local failure_context
                    failure_context="Workflow: ${run_name}
Run URL: ${html_url}

Failed Jobs (${failed_job_count}/${job_count}):
${failed_jobs_summary}

AI Analysis:
${analysis}

PR Changes:
${pr_diff}
"

                    # Send Pushover notification about agent launch
                    local agent_notification
                    agent_notification=$(printf "🤖 Launching Automated Fix Agent\n\nWorkflow: %s\nAgent Type: %s\n\nThe agent will:\n1. Analyze the failure\n2. Read project documentation\n3. Fix the issues\n4. Run all checks\n5. Create a commit (NOT push)\n\nYou will need to manually review and push the fix." "${run_name}" "${agent_type}")
                    send_pushover_notification "PR #${PR_NUMBER}: Agent Launching" "${agent_notification}" 0

                    log "INFO" "🚀 Launching ${agent_type} agent in background..."
                    log "INFO" "📋 Agent will work on: ${run_name}"
                    log "INFO" ""

                    # Launch agent in background and capture output
                    bash "${SCRIPT_DIR}/launch_fixing_agent.sh" "${PR_NUMBER}" "${agent_type}" "${failure_context}" &

                    # Mark agent as triggered for this workflow
                    state=$(echo "${state}" | jq ".agent_triggered_workflows += [${run_id}]")

                    log "INFO" "✅ ${GREEN}Agent launched successfully${NC}"
                    log "INFO" "📡 Watch the log viewer in the dashboard for real-time agent output"
                    log "INFO" ""
                    log "INFO" "⚠️  ${YELLOW}IMPORTANT: Agent will create a commit but NOT push${NC}"
                    log "INFO" "⚠️  ${YELLOW}You must manually review and push changes${NC}"
                    log "INFO" ""
                fi
            fi
        elif [[ "${conclusion}" == "success" ]]; then
            log "INFO" "${GREEN}Workflow '${run_name}' passed (${job_count} jobs)${NC}"
        fi
    done < <(echo "${workflow_runs}" | jq -c '.workflow_runs[]')

    # ============================================================
    # PIPELINE-LEVEL NOTIFICATION LOGIC
    # ============================================================
    
    # Determine current pipeline status
    local current_pipeline_status
    if [[ "${workflow_count}" -eq 0 ]]; then
        current_pipeline_status="no_workflows"
    elif [[ "${all_completed}" == "false" ]]; then
        current_pipeline_status="in_progress"
    elif [[ "${has_failures}" == "true" ]]; then
        current_pipeline_status="failed"
    else
        current_pipeline_status="success"
    fi

    # Get previous pipeline status and notification state
    local previous_pipeline_status
    previous_pipeline_status=$(echo "${state}" | jq -r '.pipeline_status // "unknown"')
    
    local pipeline_notification_sent
    pipeline_notification_sent=$(echo "${state}" | jq -r '.pipeline_notification_sent // false')

    log "INFO" "Pipeline status: ${previous_pipeline_status} -> ${current_pipeline_status}"

    # Send notification only when pipeline transitions to a completed state
    if [[ "${current_pipeline_status}" != "${previous_pipeline_status}" ]]; then
        # Pipeline status changed - reset notification flag
        state=$(echo "${state}" | jq '.pipeline_notification_sent = false')
        pipeline_notification_sent="false"
    fi

    # Send notification if pipeline completed and we haven't sent one yet
    if [[ "${pipeline_notification_sent}" == "false" ]] && [[ "${current_pipeline_status}" == "success" || "${current_pipeline_status}" == "failed" ]]; then
        if [[ "${current_pipeline_status}" == "success" ]]; then
            log "INFO" "${GREEN}Pipeline passed - sending success notification${NC}"
            send_pushover_notification "PR #${PR_NUMBER}: ${pr_title}" "✅ Pipeline passed - all workflows completed successfully!" 0
        else
            log "INFO" "${RED}Pipeline failed - sending failure notification${NC}"
            send_pushover_notification "PR #${PR_NUMBER}: ${pr_title}" "❌ Pipeline failed - one or more workflows have failed." 1
        fi
        
        # Mark notification as sent
        state=$(echo "${state}" | jq '.pipeline_notification_sent = true')
    fi

    # Update pipeline status in state
    state=$(echo "${state}" | jq --arg status "${current_pipeline_status}" '.pipeline_status = $status')

    # Legacy: Update pipeline_passed flag for backward compatibility
    if [[ "${current_pipeline_status}" == "success" ]]; then
        state=$(echo "${state}" | jq '.pipeline_passed = true')
    else
        state=$(echo "${state}" | jq '.pipeline_passed = false')
    fi

    echo "${state}"
}

# Main monitoring loop
monitor_pr() {
    log "INFO" "${BLUE}Starting PR #${PR_NUMBER} monitoring (interval: ${CHECK_INTERVAL}s)${NC}"

    # Initialize database
    db_init 2>/dev/null || log "WARN" "${YELLOW}Database initialization failed, continuing without DB logging${NC}"

    # Initialize state
    initialize_state

    # Send initial notification
    send_pushover_notification "PR Monitor Started" "Monitoring PR #${PR_NUMBER} every $((CHECK_INTERVAL / 60)) minutes" -1

    # Log activity to database
    db_log_activity "monitor_started" "PR monitor started" "Checking every ${CHECK_INTERVAL}s" "system" 2>/dev/null || true
    
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        log "INFO" "${BLUE}=== Check iteration ${iteration} at $(date) ===${NC}"
        
        # Load current state
        local state
        state=$(load_state)
        
        # Get PR details
        log "INFO" "Fetching PR details..."
        local pr_details
        pr_details=$(get_pr_details)
        
        if echo "${pr_details}" | jq -e '.message' > /dev/null 2>&1; then
            log "ERROR" "${RED}Failed to fetch PR details: $(echo "${pr_details}" | jq -r '.message')${NC}"
            sleep "${CHECK_INTERVAL}"
            continue
        fi
        
        local pr_state
        pr_state=$(echo "${pr_details}" | jq -r '.state')

        log "INFO" "PR State: ${pr_state}"

        # Update PR metadata in database
        db_update_pr "${pr_details}" 2>/dev/null || true

        if [[ "${pr_state}" == "closed" ]]; then
            log "INFO" "${YELLOW}PR #${PR_NUMBER} is closed, stopping monitoring${NC}"
            send_pushover_notification "PR Monitor Stopped" "PR #${PR_NUMBER} is closed" -1
            db_log_activity "monitor_stopped" "PR closed, monitoring stopped" "" "system" 2>/dev/null || true
            break
        fi

        # Get and process comments
        log "INFO" "Fetching PR comments..."
        local comments
        comments=$(get_pr_comments)
        state=$(process_new_comments "${comments}" "${state}")
        
        # Get and process workflow runs
        log "INFO" "Fetching workflow runs..."
        local workflow_runs
        workflow_runs=$(get_workflow_runs "${pr_details}")
        state=$(process_workflow_runs "${workflow_runs}" "${state}" "${pr_details}")
        
        # Save updated state
        save_state "${state}"

        # Log check to database
        local comment_count workflow_count failed_workflows
        comment_count=$(echo "${comments}" | jq -r '(.review_comments // [] | length) + (.issue_comments // [] | length)')
        workflow_count=$(echo "${workflow_runs}" | jq -r '.workflow_runs | length')
        failed_workflows=$(echo "${workflow_runs}" | jq -r '[.workflow_runs[] | select(.conclusion == "failure")] | length')
        db_log_check "${pr_state}" "${comment_count}" "${workflow_count}" "${failed_workflows}" "Iteration ${iteration}" 2>/dev/null || true

        log "INFO" "${BLUE}Check complete. Sleeping for ${CHECK_INTERVAL}s${NC}"
        sleep "${CHECK_INTERVAL}"
    done
}

# Cleanup on exit
cleanup() {
    log "INFO" "Cleaning up..."
    # Optionally remove state file on exit
    # rm -f "${STATE_FILE}"
}

trap cleanup EXIT INT TERM

# Main execution
main() {
    validate_inputs

    # Ensure directories exist for state and log files
    ensure_dir "${STATE_FILE}"
    ensure_dir "${LOG_FILE}"

    log "INFO" "${GREEN}Starting PR monitor for PR #${PR_NUMBER}${NC}"
    log "INFO" "Repository: ${GITHUB_REPO}"
    log "INFO" "Check interval: ${CHECK_INTERVAL}s ($((CHECK_INTERVAL / 60)) minutes)"
    log "INFO" "State file: ${STATE_FILE}"
    log "INFO" "Log file: ${LOG_FILE}"
    
    monitor_pr
}

main
