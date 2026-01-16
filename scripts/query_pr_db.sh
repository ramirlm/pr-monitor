#!/usr/bin/env bash
#
# query_pr_db.sh
# Query PR tracking database for history and status
#
# Usage:
#   ./query_pr_db.sh [COMMAND] [OPTIONS]
#
# Commands:
#   list                    - List all PRs
#   status <PR> [REPO]      - Show detailed PR status
#   comments <PR> [REPO]    - Show all comments for a PR
#   workflows <PR> [REPO]   - Show workflow runs for a PR
#   activity <PR> [REPO]    - Show activity log for a PR
#   history <PR> [REPO]     - Show check history for a PR
#   unaddressed <PR> [REPO] - Show unaddressed comments
#   mark-addressed <PR> <COMMENT_ID> [NOTES] - Mark comment as addressed

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
load_env

# Get repository root
REPO_ROOT=$(get_repo_root)

# Use provided path or default to repository-local database
DB_PATH="${DB_PATH:-${REPO_ROOT}/.pr_monitor/data/pr_tracking.db}"
COMMAND="${1:-list}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if database exists
if [[ ! -f "${DB_PATH}" ]]; then
    echo -e "${RED}Database not found at: ${DB_PATH}${NC}"
    echo "Run init_pr_db.sh first to initialize the database"
    exit 1
fi

# Helper to get PR ID
get_pr_id() {
    local pr_number="$1"
    local repo="${2:-}"

    if [[ -z "${repo}" ]]; then
        sqlite3 "${DB_PATH}" "SELECT id FROM prs WHERE pr_number=${pr_number} LIMIT 1;" 2>/dev/null || echo ""
    else
        sqlite3 "${DB_PATH}" "SELECT id FROM prs WHERE pr_number=${pr_number} AND repo='${repo}';" 2>/dev/null || echo ""
    fi
}

# Command: list all PRs
cmd_list() {
    echo -e "${BLUE}=== All Tracked PRs ===${NC}"
    echo ""

    sqlite3 -header -column "${DB_PATH}" <<'EOF'
SELECT
    pr_number AS "PR#",
    repo AS "Repository",
    state AS "State",
    author AS "Author",
    substr(title, 1, 50) AS "Title",
    datetime(updated_at, 'localtime') AS "Last Updated"
FROM prs
ORDER BY updated_at DESC;
EOF
}

# Command: show PR status
cmd_status() {
    local pr_number="$1"
    local repo="${2:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== PR #${pr_number} Status ===${NC}"
    echo ""

    # PR details
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    pr_number AS "PR Number",
    repo AS "Repository",
    state AS "State",
    author AS "Author",
    title AS "Title",
    datetime(created_at, 'localtime') AS "Created",
    datetime(updated_at, 'localtime') AS "Last Updated",
    url AS "URL"
FROM prs
WHERE id=${pr_id};
EOF

    echo ""
    echo -e "${GREEN}Comment Summary:${NC}"
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    COUNT(*) AS "Total",
    SUM(CASE WHEN addressed = 1 THEN 1 ELSE 0 END) AS "Addressed",
    SUM(CASE WHEN addressed = 0 THEN 1 ELSE 0 END) AS "Unaddressed"
FROM comments
WHERE pr_id=${pr_id};
EOF

    echo ""
    echo -e "${GREEN}Workflow Summary:${NC}"
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    COUNT(*) AS "Total Runs",
    SUM(CASE WHEN conclusion = 'success' THEN 1 ELSE 0 END) AS "Passed",
    SUM(CASE WHEN conclusion = 'failure' THEN 1 ELSE 0 END) AS "Failed",
    SUM(CASE WHEN conclusion = 'skipped' THEN 1 ELSE 0 END) AS "Skipped"
FROM workflows
WHERE pr_id=${pr_id};
EOF

    echo ""
    echo -e "${GREEN}Recent Activity:${NC}"
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    datetime(activity_time, 'localtime') AS "Time",
    activity_type AS "Type",
    substr(summary, 1, 60) AS "Summary"
FROM activities
WHERE pr_id=${pr_id}
ORDER BY activity_time DESC
LIMIT 10;
EOF
}

# Command: show comments
cmd_comments() {
    local pr_number="$1"
    local repo="${2:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== Comments for PR #${pr_number} ===${NC}"
    echo ""

    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    comment_id AS "ID",
    comment_type AS "Type",
    author AS "Author",
    substr(body, 1, 80) AS "Comment",
    file_path AS "File",
    CASE WHEN addressed = 1 THEN '✓' ELSE '✗' END AS "Addressed",
    datetime(created_at, 'localtime') AS "Created"
FROM comments
WHERE pr_id=${pr_id}
ORDER BY created_at DESC;
EOF
}

# Command: show workflows
cmd_workflows() {
    local pr_number="$1"
    local repo="${2:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== Workflow Runs for PR #${pr_number} ===${NC}"
    echo ""

    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    run_id AS "Run ID",
    workflow_name AS "Workflow",
    status AS "Status",
    conclusion AS "Conclusion",
    datetime(created_at, 'localtime') AS "Started",
    datetime(completed_at, 'localtime') AS "Completed"
FROM workflows
WHERE pr_id=${pr_id}
ORDER BY created_at DESC;
EOF

    echo ""
    echo -e "${RED}Failed Workflows:${NC}"
    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    workflow_name AS "Workflow",
    substr(failure_details, 1, 100) AS "Failure Details",
    datetime(completed_at, 'localtime') AS "Failed At"
FROM workflows
WHERE pr_id=${pr_id} AND conclusion = 'failure'
ORDER BY completed_at DESC;
EOF
}

# Command: show activity log
cmd_activity() {
    local pr_number="$1"
    local repo="${2:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== Activity Log for PR #${pr_number} ===${NC}"
    echo ""

    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    datetime(activity_time, 'localtime') AS "Time",
    activity_type AS "Type",
    actor AS "Actor",
    summary AS "Summary",
    substr(details, 1, 80) AS "Details"
FROM activities
WHERE pr_id=${pr_id}
ORDER BY activity_time DESC
LIMIT 50;
EOF
}

# Command: show check history
cmd_history() {
    local pr_number="$1"
    local repo="${2:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== Check History for PR #${pr_number} ===${NC}"
    echo ""

    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    datetime(check_time, 'localtime') AS "Check Time",
    pr_state AS "PR State",
    comment_count AS "Comments",
    workflow_count AS "Workflows",
    failed_workflows AS "Failed",
    notes AS "Notes"
FROM check_history
WHERE pr_id=${pr_id}
ORDER BY check_time DESC
LIMIT 50;
EOF
}

# Command: show unaddressed comments
cmd_unaddressed() {
    local pr_number="$1"
    local repo="${2:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    echo -e "${YELLOW}=== Unaddressed Comments for PR #${pr_number} ===${NC}"
    echo ""

    sqlite3 -header -column "${DB_PATH}" <<EOF
SELECT
    comment_id AS "Comment ID",
    comment_type AS "Type",
    author AS "Author",
    body AS "Comment",
    file_path AS "File",
    datetime(created_at, 'localtime') AS "Created"
FROM comments
WHERE pr_id=${pr_id} AND addressed = 0
ORDER BY created_at DESC;
EOF
}

# Command: mark comment as addressed
cmd_mark_addressed() {
    local pr_number="$1"
    local comment_id="$2"
    local notes="${3:-Manually marked as addressed}"
    local repo="${4:-}"
    local pr_id=$(get_pr_id "${pr_number}" "${repo}")

    if [[ -z "${pr_id}" ]]; then
        echo -e "${RED}PR #${pr_number} not found in database${NC}"
        exit 1
    fi

    notes=$(echo "${notes}" | sed "s/'/''/g")

    sqlite3 "${DB_PATH}" <<EOF
UPDATE comments SET
    addressed=1,
    addressed_at=CURRENT_TIMESTAMP,
    addressed_notes='${notes}'
WHERE comment_id=${comment_id} AND pr_id=${pr_id};
EOF

    echo -e "${GREEN}✓ Comment #${comment_id} marked as addressed${NC}"
}

# Main command dispatcher
case "${COMMAND}" in
    list)
        cmd_list
        ;;
    status)
        [[ $# -lt 2 ]] && { echo "Usage: $0 status <PR_NUMBER> [REPO]"; exit 1; }
        cmd_status "$2" "${3:-}"
        ;;
    comments)
        [[ $# -lt 2 ]] && { echo "Usage: $0 comments <PR_NUMBER> [REPO]"; exit 1; }
        cmd_comments "$2" "${3:-}"
        ;;
    workflows)
        [[ $# -lt 2 ]] && { echo "Usage: $0 workflows <PR_NUMBER> [REPO]"; exit 1; }
        cmd_workflows "$2" "${3:-}"
        ;;
    activity)
        [[ $# -lt 2 ]] && { echo "Usage: $0 activity <PR_NUMBER> [REPO]"; exit 1; }
        cmd_activity "$2" "${3:-}"
        ;;
    history)
        [[ $# -lt 2 ]] && { echo "Usage: $0 history <PR_NUMBER> [REPO]"; exit 1; }
        cmd_history "$2" "${3:-}"
        ;;
    unaddressed)
        [[ $# -lt 2 ]] && { echo "Usage: $0 unaddressed <PR_NUMBER> [REPO]"; exit 1; }
        cmd_unaddressed "$2" "${3:-}"
        ;;
    mark-addressed)
        [[ $# -lt 3 ]] && { echo "Usage: $0 mark-addressed <PR_NUMBER> <COMMENT_ID> [NOTES]"; exit 1; }
        cmd_mark_addressed "$2" "$3" "${4:-Manually marked as addressed}"
        ;;
    *)
        echo "Unknown command: ${COMMAND}"
        echo ""
        echo "Available commands:"
        echo "  list                    - List all PRs"
        echo "  status <PR> [REPO]      - Show detailed PR status"
        echo "  comments <PR> [REPO]    - Show all comments"
        echo "  workflows <PR> [REPO]   - Show workflow runs"
        echo "  activity <PR> [REPO]    - Show activity log"
        echo "  history <PR> [REPO]     - Show check history"
        echo "  unaddressed <PR> [REPO] - Show unaddressed comments"
        echo "  mark-addressed <PR> <COMMENT_ID> [NOTES] - Mark comment as addressed"
        exit 1
        ;;
esac
