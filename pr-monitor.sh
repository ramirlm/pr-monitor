#!/usr/bin/env bash
#
# pr-monitor.sh
# Main entry point for PR monitoring system
#
# Usage:
#   ./pr-monitor.sh [COMMAND] [OPTIONS]
#
# Commands:
#   start <PR>      Start monitoring a PR
#   detect          Detect and show current branch's PR
#   dashboard       Start web dashboard
#   stop <PR>       Stop monitoring a PR
#   list            List running monitors
#   help            Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "${SCRIPT_DIR}/.." && pwd)")

source "${SCRIPT_DIR}/scripts/utils.sh"
load_env

# Show usage information
show_usage() {
    cat << EOF
PR Monitor - Portable GitHub PR Monitoring System

Usage:
  ./pr-monitor.sh [COMMAND] [OPTIONS]

Commands:
  start <PR> [REPO]    Start monitoring a PR
                       Example: ./pr-monitor.sh start 123
                                ./pr-monitor.sh start 123 owner/repo

  detect               Auto-detect and show current branch's PR
                       Example: ./pr-monitor.sh detect

  dashboard            Start web dashboard (http://localhost:3000)
                       Example: ./pr-monitor.sh dashboard

  stop <PR>            Stop monitoring a PR
                       Example: ./pr-monitor.sh stop 123

  list                 List all running monitors
                       Example: ./pr-monitor.sh list

  init                 Initialize database
                       Example: ./pr-monitor.sh init

  query <CMD>          Query database (list, pr <NUM>, comments <NUM>)
                       Example: ./pr-monitor.sh query list
                                ./pr-monitor.sh query pr 123

  errors [PR]          Show detailed errors for a PR (auto-detects if not provided)
                       Example: ./pr-monitor.sh errors 123
                                ./pr-monitor.sh errors

  cleanup              Stop all monitors for duplicate PRs
                       Example: ./pr-monitor.sh cleanup

  help                 Show this help message

Environment Variables:
  GITHUB_TOKEN         GitHub personal access token (auto-detected from gh CLI)
  GITHUB_REPO          Repository in format "owner/repo" (auto-detected from git remote)
  CHECK_INTERVAL       Check interval in seconds (default: 60)

Examples:
  # Start web dashboard and monitor from UI
  ./pr-monitor.sh dashboard

  # Auto-detect and start monitoring current branch's PR
  PR_NUM=\$(./pr-monitor.sh detect)
  ./pr-monitor.sh start \$PR_NUM

  # Start monitoring specific PR
  ./pr-monitor.sh start 123 owner/repo

Setup:
  1. Copy .env.example to .env and configure (optional, auto-detection works)
  2. Run: ./pr-monitor.sh init
  3. Run: ./pr-monitor.sh dashboard

For more info, see README.md
EOF
}

# Command: start monitoring
cmd_start() {
    local pr_num="${1:-}"
    local repo="${2:-${GITHUB_REPO}}"

    if [[ -z "${pr_num}" ]]; then
        log_message "ERROR" "PR number is required"
        echo "Usage: $0 start <PR_NUMBER> [REPO]"
        exit 1
    fi

    # Check if monitor is already running for this PR
    local existing_monitors
    existing_monitors=$(ps aux | grep "check_pr_status.sh ${pr_num}" | grep -v grep || true)

    if [[ -n "${existing_monitors}" ]]; then
        echo "⚠️  Monitor is already running for PR #${pr_num}"
        echo ""
        echo "Running monitors:"
        echo "${existing_monitors}" | while read -r line; do
            local pid=$(echo "${line}" | awk '{print $2}')
            local time=$(echo "${line}" | awk '{print $10}')
            echo "  PID: ${pid} - Running: ${time}"
        done
        echo ""
        echo "To stop existing monitors: ./pr-monitor.sh stop ${pr_num}"
        echo "To force start anyway, first stop the existing monitor"
        exit 1
    fi

    log_message "INFO" "Starting monitor for PR #${pr_num}"

    # Start monitor in background
    bash "${SCRIPT_DIR}/scripts/check_pr_status.sh" "${pr_num}" "${repo}" &
    local pid=$!

    echo "✅ Monitor started for PR #${pr_num} (PID: ${pid})"
    echo "📁 Repository: ${repo}"
    echo "📄 Log file: ${REPO_ROOT}/.pr_monitor/logs/pr_${pr_num}.log"
    echo ""
    echo "To stop: ./pr-monitor.sh stop ${pr_num}"
    echo "To view logs: tail -f ${REPO_ROOT}/.pr_monitor/logs/pr_${pr_num}.log"
}

# Command: detect current PR
cmd_detect() {
    local pr_num
    pr_num=$(detect_current_pr)

    if [[ -n "${pr_num}" ]]; then
        local branch
        branch=$(git branch --show-current 2>/dev/null)

        # Get PR details
        local pr_info
        pr_info=$(gh pr view "${pr_num}" --json number,title,url 2>/dev/null || echo "{}")

        if [[ "${pr_info}" != "{}" ]]; then
            local title
            title=$(echo "${pr_info}" | jq -r '.title')
            local url
            url=$(echo "${pr_info}" | jq -r '.url')

            echo "✅ Detected PR #${pr_num}"
            echo "Branch: ${branch}"
            echo "Title: ${title}"
            echo "URL: ${url}"
            echo ""
            echo "To start monitoring: ./pr-monitor.sh start ${pr_num}"
        else
            echo "${pr_num}"
        fi
    else
        log_message "ERROR" "No PR found for current branch"
        exit 1
    fi
}

# Command: start dashboard
cmd_dashboard() {
    log_message "INFO" "Starting web dashboard..."

    cd "${SCRIPT_DIR}/dashboard"

    # Install dependencies if needed
    if [[ ! -d node_modules ]]; then
        log_message "INFO" "Installing dependencies..."
        npm install
    fi

    # Build frontend if needed
    if [[ ! -f dist/server-simple.js ]]; then
        log_message "INFO" "Building frontend..."
        npm run build
    fi

    # Set DB path and start server
    export DB_PATH="${SCRIPT_DIR}/data/pr_tracking.db"

    log_message "INFO" "Dashboard starting at http://localhost:3000"
    npm start
}

# Command: stop monitoring
cmd_stop() {
    local pr_num="${1:-}"

    if [[ -z "${pr_num}" ]]; then
        log_message "ERROR" "PR number is required"
        echo "Usage: $0 stop <PR_NUMBER>"
        exit 1
    fi

    # Find all monitors for this PR
    local existing_monitors
    existing_monitors=$(ps aux | grep "check_pr_status.sh ${pr_num}" | grep -v grep || true)

    if [[ -z "${existing_monitors}" ]]; then
        echo "⚠️  No monitor found for PR #${pr_num}"
        exit 1
    fi

    # Count monitors
    local monitor_count
    monitor_count=$(echo "${existing_monitors}" | wc -l | tr -d ' ')

    log_message "INFO" "Stopping ${monitor_count} monitor(s) for PR #${pr_num}"

    # Kill all monitors for this PR
    if pkill -f "check_pr_status.sh ${pr_num}"; then
        echo "✅ Stopped ${monitor_count} monitor(s) for PR #${pr_num}"

        # Verify they're all dead
        sleep 1
        local still_running
        still_running=$(ps aux | grep "check_pr_status.sh ${pr_num}" | grep -v grep || true)

        if [[ -n "${still_running}" ]]; then
            echo "⚠️  Some monitors didn't stop gracefully, force killing..."
            pkill -9 -f "check_pr_status.sh ${pr_num}" || true
            echo "✅ Force stopped all monitors"
        fi
    else
        echo "❌ Failed to stop monitor(s) for PR #${pr_num}"
        exit 1
    fi
}

# Command: list running monitors
cmd_list() {
    echo "Running PR Monitors:"
    echo ""

    local count=0
    while read -r line; do
        if [[ -n "${line}" ]]; then
            local pid=$(echo "${line}" | awk '{print $2}')
            local pr_num=$(echo "${line}" | grep -o 'check_pr_status.sh [0-9]\+' | awk '{print $2}')
            local time=$(echo "${line}" | awk '{print $10}')

            echo "  PR #${pr_num} - PID: ${pid} - Running: ${time}"
            count=$((count + 1))
        fi
    done < <(ps aux | grep "check_pr_status.sh" | grep -v grep || true)

    if [[ ${count} -eq 0 ]]; then
        echo "  No monitors running"
    fi

    echo ""
    echo "To stop a monitor: ./pr-monitor.sh stop <PR_NUMBER>"
}

# Command: initialize database
cmd_init() {
    log_message "INFO" "Initializing database..."
    bash "${SCRIPT_DIR}/scripts/init_pr_db.sh"
}

# Command: query database
cmd_query() {
    shift # Remove 'query' from args
    bash "${SCRIPT_DIR}/scripts/query_pr_db.sh" "$@"
}

# Command: show errors for a PR
cmd_errors() {
    local pr_num="${1:-}"

    if [[ -z "${pr_num}" ]]; then
        # Try to detect from current branch
        pr_num=$(detect_current_pr)
    fi

    if [[ -z "${pr_num}" ]]; then
        log_message "ERROR" "PR number is required"
        echo "Usage: $0 errors <PR_NUMBER>"
        exit 1
    fi

    bash "${SCRIPT_DIR}/scripts/show_pr_errors.sh" "${pr_num}"
}

# Main command dispatcher
main() {
    local command="${1:-help}"

    case "${command}" in
        start)
            shift
            cmd_start "$@"
            ;;

        detect)
            cmd_detect
            ;;

        dashboard)
            cmd_dashboard
            ;;

        stop)
            shift
            cmd_stop "$@"
            ;;

        list)
            cmd_list
            ;;

        init)
            cmd_init
            ;;

        query)
            cmd_query "$@"
            ;;

        errors)
            shift
            cmd_errors "$@"
            ;;

        cleanup)
            cmd_cleanup
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            echo "Unknown command: ${command}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Command: cleanup duplicate monitors
cmd_cleanup() {
    echo "🔍 Checking for duplicate monitors..."
    echo ""

    local all_monitors
    all_monitors=$(ps aux | grep "check_pr_status.sh" | grep -v grep || true)

    if [[ -z "${all_monitors}" ]]; then
        echo "✅ No monitors running"
        exit 0
    fi

    # Get unique PR numbers
    local pr_numbers
    pr_numbers=$(echo "${all_monitors}" | grep -o 'check_pr_status.sh [0-9]\+' | awk '{print $2}' | sort -u)

    local has_duplicates=false

    # Check each PR for duplicates
    while read -r pr_num; do
        [[ -z "${pr_num}" ]] && continue

        # Get all PIDs for this PR
        local pr_pids
        pr_pids=$(ps aux | grep "check_pr_status.sh ${pr_num}" | grep -v grep | awk '{print $2}')
        local pid_array=($pr_pids)
        local count=${#pid_array[@]}

        if [[ ${count} -gt 1 ]]; then
            has_duplicates=true
            echo "⚠️  PR #${pr_num} has ${count} monitors running:"
            for pid in "${pid_array[@]}"; do
                echo "   PID: ${pid}"
            done

            # Stop all but the first one
            echo "   Stopping duplicate monitors..."
            for ((i=1; i<${count}; i++)); do
                local pid_to_kill="${pid_array[$i]}"
                kill "${pid_to_kill}" 2>/dev/null || kill -9 "${pid_to_kill}" 2>/dev/null || true
                echo "   ✅ Stopped PID ${pid_to_kill}"
            done
            echo ""
        fi
    done <<< "${pr_numbers}"

    if [[ "${has_duplicates}" == "false" ]]; then
        echo "✅ No duplicate monitors found"
        echo ""
        echo "Current monitors:"
        cmd_list
    else
        echo "✅ Cleanup complete"
        echo ""
        echo "Remaining monitors:"
        cmd_list
    fi
}

main "$@"
