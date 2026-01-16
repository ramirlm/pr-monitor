#!/usr/bin/env bash
#
# classify_failure.sh
# Classify PR failures and determine appropriate fixing agent
#
# Usage: classify_failure.sh <failure_type> <failure_details>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Classify failure type and return agent type
classify_failure() {
    local failure_type="$1"
    local failure_details="$2"
    local workflow_name="${3:-}"

    # E2E Test Failures
    if echo "${workflow_name}" | grep -qi "E2E"; then
        echo "e2e-fix"
        return 0
    fi

    # Lint failures
    if echo "${workflow_name}" | grep -qi "lint"; then
        echo "lint-fix"
        return 0
    fi

    # Type check failures
    if echo "${workflow_name}" | grep -qi "type"; then
        echo "type-fix"
        return 0
    fi

    # Build failures
    if echo "${workflow_name}" | grep -qi "build"; then
        echo "build-fix"
        return 0
    fi

    # Integration test failures
    if echo "${workflow_name}" | grep -qi "integration"; then
        echo "integration-fix"
        return 0
    fi

    # Unit test failures
    if echo "${workflow_name}" | grep -qi "test" || echo "${workflow_name}" | grep -qi "unit"; then
        echo "unit-test-fix"
        return 0
    fi

    # API compatibility failures
    if echo "${workflow_name}" | grep -qi "api" || echo "${workflow_name}" | grep -qi "compatibility"; then
        echo "api-fix"
        return 0
    fi

    # Default: general code fix
    echo "general-fix"
    return 0
}

# Get human-readable agent description
get_agent_description() {
    local agent_type="$1"

    case "${agent_type}" in
        e2e-fix)
            echo "E2E Test Fixing Agent (reads E2E docs, fixes tests, ensures all checks pass)"
            ;;
        lint-fix)
            echo "Linting Agent (fixes code style issues)"
            ;;
        type-fix)
            echo "TypeScript Type Fixing Agent (resolves type errors)"
            ;;
        build-fix)
            echo "Build Fixing Agent (resolves build failures)"
            ;;
        integration-fix)
            echo "Integration Test Fixing Agent (fixes integration test failures)"
            ;;
        unit-test-fix)
            echo "Unit Test Fixing Agent (fixes unit test failures)"
            ;;
        api-fix)
            echo "API Compatibility Fixing Agent (ensures API compliance)"
            ;;
        general-fix)
            echo "General Code Fixing Agent (investigates and fixes code issues)"
            ;;
        *)
            echo "Unknown Agent Type"
            ;;
    esac
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-}"
    ARG1="${2:-}"
    ARG2="${3:-}"

    if [[ -z "${COMMAND}" ]]; then
        echo "Usage: $0 <failure_type> <failure_details> [workflow_name]"
        echo "   or: $0 get_description <agent_type>"
        exit 1
    fi

    # Handle get_description command
    if [[ "${COMMAND}" == "get_description" ]]; then
        get_agent_description "${ARG1}"
        exit 0
    fi

    # Otherwise treat as classification
    FAILURE_TYPE="${COMMAND}"
    FAILURE_DETAILS="${ARG1}"
    WORKFLOW_NAME="${ARG2}"

    AGENT_TYPE=$(classify_failure "${FAILURE_TYPE}" "${FAILURE_DETAILS}" "${WORKFLOW_NAME}")
    echo "${AGENT_TYPE}"
fi
