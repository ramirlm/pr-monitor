#!/usr/bin/env bash
# Shared utilities for PR monitoring system
# Functions for configuration loading, PR detection, and path management

# Get repository root directory
get_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}

# Load environment configuration from .env file
# Auto-detects GITHUB_REPO and GITHUB_TOKEN if not set
load_env() {
    local repo_root
    repo_root=$(get_repo_root)

    # Load .env file if it exists
    if [[ -f "${repo_root}/.pr_monitor/.env" ]]; then
        set -a
        source "${repo_root}/.pr_monitor/.env"
        set +a
    fi

    # Auto-detect GITHUB_REPO from git remote if not set
    if [[ -z "${GITHUB_REPO:-}" ]]; then
        GITHUB_REPO=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/](.+/[^/]+)(\.git)?$|\1|' | sed 's/\.git$//')
        export GITHUB_REPO
    fi

    # Auto-detect GITHUB_TOKEN from gh CLI if not set
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
        export GITHUB_TOKEN
    fi

    # Set default CHECK_INTERVAL if not set
    if [[ -z "${CHECK_INTERVAL:-}" ]]; then
        CHECK_INTERVAL=60
        export CHECK_INTERVAL
    fi

    # Set default CLAUDE_CLI if not set
    if [[ -z "${CLAUDE_CLI:-}" ]]; then
        CLAUDE_CLI="claude"
        export CLAUDE_CLI
    fi
}

# Detect PR number for current Git branch
# Returns: PR number or empty string if not found
# Usage: pr_num=$(detect_current_pr)
detect_current_pr() {
    local branch
    branch=$(git branch --show-current 2>/dev/null)

    if [[ -z "${branch}" ]]; then
        echo "" >&2
        return 1
    fi

    local pr_number
    pr_number=$(gh pr list --head "${branch}" --json number --jq '.[0].number' 2>/dev/null)

    echo "${pr_number:-}"
}

# Get path to state file for a PR
# Usage: state_file=$(get_state_file 123)
get_state_file() {
    local pr_number="$1"
    local repo_root
    repo_root=$(get_repo_root)
    echo "${repo_root}/.pr_monitor/data/state/pr_${pr_number}.json"
}

# Get path to log file for a PR
# Usage: log_file=$(get_log_file 123)
get_log_file() {
    local pr_number="$1"
    local repo_root
    repo_root=$(get_repo_root)
    echo "${repo_root}/.pr_monitor/logs/pr_${pr_number}.log"
}

# Get path to database file
# Usage: db_path=$(get_db_path)
get_db_path() {
    local repo_root
    repo_root=$(get_repo_root)
    echo "${repo_root}/.pr_monitor/data/pr_tracking.db"
}

# Ensure directory exists for a file path
# Usage: ensure_dir "/path/to/file.txt"
ensure_dir() {
    local file_path="$1"
    local dir
    dir=$(dirname "${file_path}")
    mkdir -p "${dir}"
}

# Log message with timestamp
# Usage: log_message "INFO" "Message text"
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}"
}

# Check if required commands are available
# Usage: check_requirements "gh" "git" "sqlite3"
check_requirements() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "${cmd}" &> /dev/null; then
            missing+=("${cmd}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required commands: ${missing[*]}"
        return 1
    fi
    return 0
}

# Validate GitHub token and repository
# Returns: 0 if valid, 1 if invalid
validate_github_config() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_message "ERROR" "GITHUB_TOKEN not set. Run 'gh auth login' or set in .env"
        return 1
    fi

    if [[ -z "${GITHUB_REPO:-}" ]]; then
        log_message "ERROR" "GITHUB_REPO not set. Ensure you're in a git repository with GitHub remote"
        return 1
    fi

    # Verify token works
    if ! gh api user &> /dev/null; then
        log_message "ERROR" "Invalid GITHUB_TOKEN or network issue"
        return 1
    fi

    return 0
}
