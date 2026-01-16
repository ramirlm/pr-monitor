#!/usr/bin/env bash
#
# launch_fixing_agent.sh
# Launch specialized Claude agent to fix PR issues
#
# Usage: launch_fixing_agent.sh <pr_number> <agent_type> <failure_context>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(get_repo_root)

source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/classify_failure.sh"
load_env

PR_NUMBER="${1:-}"
AGENT_TYPE="${2:-}"
FAILURE_CONTEXT="${3:-}"

if [[ -z "${PR_NUMBER}" ]] || [[ -z "${AGENT_TYPE}" ]]; then
    echo "Usage: $0 <pr_number> <agent_type> <failure_context>"
    exit 1
fi

LOG_FILE="${REPO_ROOT}/.pr_monitor/logs/pr_${PR_NUMBER}.log"

# Logging function that writes to PR log
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Get agent description
AGENT_DESC=$(get_agent_description "${AGENT_TYPE}")

log "INFO" "🤖 ${BLUE}===================================================${NC}"
log "INFO" "🤖 ${BLUE}LAUNCHING SPECIALIZED FIXING AGENT${NC}"
log "INFO" "🤖 ${BLUE}===================================================${NC}"
log "INFO" "📋 PR Number: ${PR_NUMBER}"
log "INFO" "🔧 Agent Type: ${AGENT_TYPE}"
log "INFO" "📝 Agent: ${AGENT_DESC}"
log "INFO" ""

# Navigate to repository root
cd "${REPO_ROOT}"

log "INFO" "📍 Working directory: ${REPO_ROOT}"
log "INFO" "🌿 Current branch: $(git branch --show-current)"
log "INFO" ""

# Create agent prompt based on type
create_agent_prompt() {
    local agent_type="$1"
    local failure_context="$2"

    case "${agent_type}" in
        e2e-fix)
            cat <<EOF
You are a specialized E2E Test Fixing Agent for PR #${PR_NUMBER}.

**Your Task:**
Fix the failing E2E tests in this PR. The tests are failing with the following context:

${failure_context}

**Important Instructions:**
1. First, read ALL E2E testing documentation in this repository (look for files like CLAUDE.md, E2E-TESTING.md, .claude/memories/e2e-testing.md, etc.)
2. Understand the project's E2E testing best practices and patterns
3. Investigate the failing tests and identify the root cause
4. Fix the issues following the project's conventions
5. Run ALL quality checks to ensure everything passes:
   - pnpm lint
   - pnpm typecheck
   - pnpm build
   - pnpm test (unit tests)
   - pnpm e2e (E2E tests)
6. Create a commit with a clear message explaining what was fixed
7. DO NOT PUSH - only create the commit locally

**Output Requirements:**
- Log every step you take so the user can see your progress in real-time
- If you find documentation, quote relevant sections
- Show all command outputs
- Explain your reasoning for each fix
- Confirm all checks pass before committing

Begin your work now. Be thorough and methodical.
EOF
            ;;
        lint-fix)
            cat <<EOF
You are a specialized Linting Agent for PR #${PR_NUMBER}.

**Your Task:**
Fix all linting issues in this PR.

${failure_context}

**Instructions:**
1. Run \`pnpm lint\` to see all issues
2. Fix issues following project conventions (check CLAUDE.md, .eslintrc, etc.)
3. Run \`pnpm lint:fix\` if available
4. Verify all checks pass: lint, typecheck, build
5. Create a commit: "fix: resolve linting issues"
6. DO NOT PUSH

Log all steps clearly.
EOF
            ;;
        type-fix)
            cat <<EOF
You are a specialized TypeScript Fixing Agent for PR #${PR_NUMBER}.

**Your Task:**
Fix TypeScript type errors in this PR.

${failure_context}

**Instructions:**
1. Run \`pnpm typecheck\` to identify all type errors
2. Read project TypeScript configuration and type patterns
3. Fix type errors systematically
4. Ensure no \`any\` types are introduced
5. Verify all checks pass
6. Create a commit: "fix: resolve TypeScript type errors"
7. DO NOT PUSH

Log all steps clearly.
EOF
            ;;
        build-fix)
            cat <<EOF
You are a specialized Build Fixing Agent for PR #${PR_NUMBER}.

**Your Task:**
Fix build failures in this PR.

${failure_context}

**Instructions:**
1. Run \`pnpm build\` to reproduce the failure
2. Investigate the root cause (missing dependencies, import errors, etc.)
3. Fix the build issues
4. Verify the build completes successfully
5. Run all other checks (lint, typecheck, test)
6. Create a commit: "fix: resolve build failures"
7. DO NOT PUSH

Log all steps clearly.
EOF
            ;;
        *)
            cat <<EOF
You are a specialized Code Fixing Agent for PR #${PR_NUMBER}.

**Your Task:**
Investigate and fix the failing checks in this PR.

${failure_context}

**Instructions:**
1. Read project documentation to understand conventions
2. Investigate the failure
3. Fix the issues following project patterns
4. Run all quality checks
5. Create a commit with a clear message
6. DO NOT PUSH

Log all steps clearly.
EOF
            ;;
    esac
}

# Generate prompt
PROMPT=$(create_agent_prompt "${AGENT_TYPE}" "${FAILURE_CONTEXT}")

log "INFO" "🚀 ${GREEN}Starting Claude agent...${NC}"
log "INFO" ""

# Check if Claude CLI is available
if ! command -v "${CLAUDE_CLI}" &> /dev/null; then
    log "ERROR" "${RED}Claude CLI not found at: ${CLAUDE_CLI}${NC}"
    log "ERROR" "${RED}Please install Claude CLI or set CLAUDE_CLI environment variable${NC}"
    exit 1
fi

# Launch Claude agent with output streaming to log
log "INFO" "📡 ${CYAN}Streaming agent output (this may take several minutes)...${NC}"
log "INFO" ""
log "INFO" "╔════════════════════════════════════════════════════════════════╗"
log "INFO" "║                     AGENT OUTPUT START                          ║"
log "INFO" "╚════════════════════════════════════════════════════════════════╝"
log "INFO" ""

# Execute Claude with the prompt, streaming output to log
{
    echo "${PROMPT}" | "${CLAUDE_CLI}" 2>&1 | while IFS= read -r line; do
        log "AGENT" "${line}"
    done
} || {
    EXIT_CODE=$?
    log "ERROR" ""
    log "ERROR" "╔════════════════════════════════════════════════════════════════╗"
    log "ERROR" "║                      AGENT FAILED                               ║"
    log "ERROR" "╚════════════════════════════════════════════════════════════════╝"
    log "ERROR" "${RED}Agent execution failed with exit code: ${EXIT_CODE}${NC}"
    exit ${EXIT_CODE}
}

log "INFO" ""
log "INFO" "╔════════════════════════════════════════════════════════════════╗"
log "INFO" "║                     AGENT OUTPUT END                            ║"
log "INFO" "╚════════════════════════════════════════════════════════════════╝"
log "INFO" ""

# Check if agent created a commit
if git log -1 --pretty=%B | grep -qi "fix"; then
    COMMIT_MSG=$(git log -1 --pretty=%B)
    COMMIT_SHA=$(git log -1 --pretty=%h)

    log "INFO" "✅ ${GREEN}Agent completed successfully!${NC}"
    log "INFO" "📝 Commit created: ${COMMIT_SHA}"
    log "INFO" "💬 Message: ${COMMIT_MSG}"
    log "INFO" ""
    log "INFO" "⚠️  ${YELLOW}IMPORTANT: Commit created but NOT pushed${NC}"
    log "INFO" "⚠️  ${YELLOW}Please review the changes and push manually if approved${NC}"
    log "INFO" ""
    log "INFO" "To review changes:"
    log "INFO" "  git show ${COMMIT_SHA}"
    log "INFO" ""
    log "INFO" "To push changes:"
    log "INFO" "  git push origin $(git branch --show-current)"
else
    log "WARN" "${YELLOW}Agent completed but no fix commit was detected${NC}"
    log "WARN" "Check the agent output above for details"
fi

log "INFO" ""
log "INFO" "🤖 ${BLUE}===================================================${NC}"
log "INFO" "🤖 ${BLUE}AGENT EXECUTION COMPLETE${NC}"
log "INFO" "🤖 ${BLUE}===================================================${NC}"
