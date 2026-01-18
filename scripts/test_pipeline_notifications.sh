#!/usr/bin/env bash
#
# test_pipeline_notifications.sh
# Unit test for pipeline notification logic
# Tests that notifications are sent once per pipeline completion

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"
    local detail="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "${result}" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} ${test_name}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} ${test_name}"
        if [[ -n "${detail}" ]]; then
            echo -e "  ${RED}${detail}${NC}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "============================================"
echo "Testing Pipeline Notification Logic"
echo "============================================"
echo ""

# Test helper: Simulate pipeline status determination
determine_pipeline_status() {
    local workflow_count="$1"
    local all_completed="$2"
    local has_failures="$3"
    
    if [[ "${workflow_count}" -eq 0 ]]; then
        echo "no_workflows"
    elif [[ "${all_completed}" == "false" ]]; then
        echo "in_progress"
    elif [[ "${has_failures}" == "true" ]]; then
        echo "failed"
    else
        echo "success"
    fi
}

# Test helper: Check if notification should be sent
should_send_notification() {
    local previous_status="$1"
    local current_status="$2"
    local notification_sent="$3"
    
    # Reset flag if status changed
    if [[ "${current_status}" != "${previous_status}" ]]; then
        notification_sent="false"
    fi
    
    # Send if completed and not sent
    if [[ "${notification_sent}" == "false" ]] && [[ "${current_status}" == "success" || "${current_status}" == "failed" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Test 1: No workflows
echo "Test 1: No workflows"
result=$(determine_pipeline_status 0 "true" "false")
if [[ "${result}" == "no_workflows" ]]; then
    test_result "No workflows detected" "PASS"
else
    test_result "No workflows detected" "FAIL" "Expected: no_workflows, Got: ${result}"
fi

# Test 2: Workflows in progress
echo ""
echo "Test 2: Workflows in progress"
result=$(determine_pipeline_status 3 "false" "false")
if [[ "${result}" == "in_progress" ]]; then
    test_result "In progress detected" "PASS"
else
    test_result "In progress detected" "FAIL" "Expected: in_progress, Got: ${result}"
fi

# Test 3: All workflows completed successfully
echo ""
echo "Test 3: All workflows completed successfully"
result=$(determine_pipeline_status 3 "true" "false")
if [[ "${result}" == "success" ]]; then
    test_result "Success detected" "PASS"
else
    test_result "Success detected" "FAIL" "Expected: success, Got: ${result}"
fi

# Test 4: All workflows completed with failures
echo ""
echo "Test 4: All workflows completed with failures"
result=$(determine_pipeline_status 3 "true" "true")
if [[ "${result}" == "failed" ]]; then
    test_result "Failure detected" "PASS"
else
    test_result "Failure detected" "FAIL" "Expected: failed, Got: ${result}"
fi

# Test 5: Notification sent on first success
echo ""
echo "Test 5: Notification sent on first success"
result=$(should_send_notification "in_progress" "success" "false")
if [[ "${result}" == "true" ]]; then
    test_result "Notification sent on first success" "PASS"
else
    test_result "Notification sent on first success" "FAIL" "Expected: true, Got: ${result}"
fi

# Test 6: Notification NOT sent on second success (duplicate prevention)
echo ""
echo "Test 6: Notification NOT sent on second success (duplicate prevention)"
result=$(should_send_notification "success" "success" "true")
if [[ "${result}" == "false" ]]; then
    test_result "Duplicate notification prevented" "PASS"
else
    test_result "Duplicate notification prevented" "FAIL" "Expected: false, Got: ${result}"
fi

# Test 7: Notification sent on first failure
echo ""
echo "Test 7: Notification sent on first failure"
result=$(should_send_notification "in_progress" "failed" "false")
if [[ "${result}" == "true" ]]; then
    test_result "Notification sent on first failure" "PASS"
else
    test_result "Notification sent on first failure" "FAIL" "Expected: true, Got: ${result}"
fi

# Test 8: Notification NOT sent on second failure (duplicate prevention)
echo ""
echo "Test 8: Notification NOT sent on second failure (duplicate prevention)"
result=$(should_send_notification "failed" "failed" "true")
if [[ "${result}" == "false" ]]; then
    test_result "Duplicate notification prevented" "PASS"
else
    test_result "Duplicate notification prevented" "FAIL" "Expected: false, Got: ${result}"
fi

# Test 9: Notification flag reset when status changes
echo ""
echo "Test 9: Notification flag reset when status changes"
result=$(should_send_notification "success" "in_progress" "true")
if [[ "${result}" == "false" ]]; then
    test_result "No notification during in_progress" "PASS"
else
    test_result "No notification during in_progress" "FAIL" "Expected: false, Got: ${result}"
fi

# Test 10: Notification resent after status change cycle
echo ""
echo "Test 10: Notification resent after status change cycle"
# Status changed from success to in_progress, then to failed
# Flag was reset on status change, so notification should be sent
result=$(should_send_notification "in_progress" "failed" "false")
if [[ "${result}" == "true" ]]; then
    test_result "Notification sent after status cycle" "PASS"
else
    test_result "Notification sent after status cycle" "FAIL" "Expected: true, Got: ${result}"
fi

# Test 11: No notification for in_progress status
echo ""
echo "Test 11: No notification for in_progress status"
result=$(should_send_notification "unknown" "in_progress" "false")
if [[ "${result}" == "false" ]]; then
    test_result "No notification for in_progress" "PASS"
else
    test_result "No notification for in_progress" "FAIL" "Expected: false, Got: ${result}"
fi

# Test 12: No notification for no_workflows status
echo ""
echo "Test 12: No notification for no_workflows status"
result=$(should_send_notification "unknown" "no_workflows" "false")
if [[ "${result}" == "false" ]]; then
    test_result "No notification for no_workflows" "PASS"
else
    test_result "No notification for no_workflows" "FAIL" "Expected: false, Got: ${result}"
fi

# Summary
echo ""
echo "============================================"
echo "Test Summary"
echo "============================================"
echo -e "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
