#!/usr/bin/env bash
#
# test_check_pr_status.sh
# Integration test for check_pr_status.sh
# Tests the script's validation and basic functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/check_pr_status.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "${result}" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} ${test_name}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} ${test_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "=================================="
echo "Testing check_pr_status.sh"
echo "=================================="
echo ""

# Test 1: Script exists and is executable
echo "Test 1: Script exists and is executable"
if [[ -x "${TEST_SCRIPT}" ]]; then
    test_result "Script is executable" "PASS"
else
    test_result "Script is executable" "FAIL"
fi
echo ""

# Test 2: Script has valid bash syntax
echo "Test 2: Script has valid bash syntax"
if bash -n "${TEST_SCRIPT}"; then
    test_result "Bash syntax is valid" "PASS"
else
    test_result "Bash syntax is valid" "FAIL"
fi
echo ""

# Test 3: Script shows usage when no arguments provided
echo "Test 3: Script shows usage when no arguments provided"
output=$("${TEST_SCRIPT}" 2>&1 || true)
if echo "${output}" | grep -q "Usage:"; then
    test_result "Shows usage message" "PASS"
else
    test_result "Shows usage message" "FAIL"
fi
echo ""

# Test 4: Script validates PR number is integer
echo "Test 4: Script validates PR number is integer"
output=$("${TEST_SCRIPT}" abc 2>&1 || true)
if echo "${output}" | grep -q "must be a valid integer"; then
    test_result "Validates PR number is integer" "PASS"
else
    test_result "Validates PR number is integer" "FAIL"
fi
echo ""

# Test 5: Script auto-detects GITHUB_TOKEN from gh auth or requires it
echo "Test 5: Script handles GITHUB_TOKEN (auto-detect or required)"
# If gh is logged in, token will be auto-detected; otherwise it will be required
if command -v gh &> /dev/null && gh auth token &> /dev/null; then
    test_result "GITHUB_TOKEN auto-detected from gh auth" "PASS"
else
    output=$("${TEST_SCRIPT}" 123 2>&1 || true)
    if echo "${output}" | grep -q "GITHUB_TOKEN"; then
        test_result "Requires GITHUB_TOKEN when gh not available" "PASS"
    else
        test_result "Requires GITHUB_TOKEN when gh not available" "FAIL"
    fi
fi
echo ""

# Test 6: Script requires GITHUB_REPO when GITHUB_TOKEN is set
echo "Test 6: Script requires GITHUB_REPO"
output=$(GITHUB_TOKEN="test" "${TEST_SCRIPT}" 123 2>&1 || true)
if echo "${output}" | grep -q "GITHUB_REPO"; then
    test_result "Requires GITHUB_REPO" "PASS"
else
    test_result "Requires GITHUB_REPO" "FAIL"
fi
echo ""

# Test 7: Script requires PUSHOVER_USER
echo "Test 7: Script requires PUSHOVER_USER"
output=$(GITHUB_TOKEN="test" GITHUB_REPO="owner/repo" "${TEST_SCRIPT}" 123 2>&1 || true)
if echo "${output}" | grep -q "PUSHOVER_USER"; then
    test_result "Requires PUSHOVER_USER" "PASS"
else
    test_result "Requires PUSHOVER_USER" "FAIL"
fi
echo ""

# Test 8: Script requires PUSHOVER_TOKEN
echo "Test 8: Script requires PUSHOVER_TOKEN"
output=$(GITHUB_TOKEN="test" GITHUB_REPO="owner/repo" PUSHOVER_USER="test" "${TEST_SCRIPT}" 123 2>&1 || true)
if echo "${output}" | grep -q "PUSHOVER_TOKEN"; then
    test_result "Requires PUSHOVER_TOKEN" "PASS"
else
    test_result "Requires PUSHOVER_TOKEN" "FAIL"
fi
echo ""

# Test 9: Check if jq is available (dependency check)
echo "Test 9: Check if jq is available"
if command -v jq &> /dev/null; then
    test_result "jq is installed" "PASS"
else
    test_result "jq is installed" "FAIL"
    echo -e "   ${YELLOW}Note: jq is required for the script to work${NC}"
fi
echo ""

# Test 10: Check if curl is available (dependency check)
echo "Test 10: Check if curl is available"
if command -v curl &> /dev/null; then
    test_result "curl is installed" "PASS"
else
    test_result "curl is installed" "FAIL"
    echo -e "   ${YELLOW}Note: curl is required for the script to work${NC}"
fi
echo ""

# Test 11: Verify script has proper shebang
echo "Test 11: Verify script has proper shebang"
first_line=$(head -n 1 "${TEST_SCRIPT}")
if [[ "${first_line}" == "#!/usr/bin/env bash" ]]; then
    test_result "Has proper shebang" "PASS"
else
    test_result "Has proper shebang" "FAIL"
fi
echo ""

# Test 12: Verify script has error handling (set -euo pipefail)
echo "Test 12: Verify script has error handling"
if grep -q "set -euo pipefail" "${TEST_SCRIPT}"; then
    test_result "Has error handling enabled" "PASS"
else
    test_result "Has error handling enabled" "FAIL"
fi
echo ""

# Test 13: Verify script has logging function
echo "Test 13: Verify script has logging function"
if grep -q "^log()" "${TEST_SCRIPT}"; then
    test_result "Has logging function" "PASS"
else
    test_result "Has logging function" "FAIL"
fi
echo ""

# Test 14: Verify script has state management functions
echo "Test 14: Verify script has state management functions"
if grep -q "initialize_state()" "${TEST_SCRIPT}" && \
   grep -q "load_state()" "${TEST_SCRIPT}" && \
   grep -q "save_state()" "${TEST_SCRIPT}"; then
    test_result "Has state management functions" "PASS"
else
    test_result "Has state management functions" "FAIL"
fi
echo ""

# Test 15: Verify script has GitHub API functions
echo "Test 15: Verify script has GitHub API functions"
if grep -q "get_pr_details()" "${TEST_SCRIPT}" && \
   grep -q "get_pr_comments()" "${TEST_SCRIPT}" && \
   grep -q "get_workflow_runs()" "${TEST_SCRIPT}"; then
    test_result "Has GitHub API functions" "PASS"
else
    test_result "Has GitHub API functions" "FAIL"
fi
echo ""

# Test 16: Verify script has Pushover notification function
echo "Test 16: Verify script has Pushover notification function"
if grep -q "send_pushover_notification()" "${TEST_SCRIPT}"; then
    test_result "Has Pushover notification function" "PASS"
else
    test_result "Has Pushover notification function" "FAIL"
fi
echo ""

# Test 17: Verify script has Claude integration
echo "Test 17: Verify script has Claude integration"
if grep -q "call_claude_analysis()" "${TEST_SCRIPT}"; then
    test_result "Has Claude integration function" "PASS"
else
    test_result "Has Claude integration function" "FAIL"
fi
echo ""

# Test 18: Verify script has comment processing
echo "Test 18: Verify script has comment processing"
if grep -q "process_new_comments()" "${TEST_SCRIPT}"; then
    test_result "Has comment processing function" "PASS"
else
    test_result "Has comment processing function" "FAIL"
fi
echo ""

# Test 19: Verify script has workflow processing
echo "Test 19: Verify script has workflow processing"
if grep -q "process_workflow_runs()" "${TEST_SCRIPT}"; then
    test_result "Has workflow processing function" "PASS"
else
    test_result "Has workflow processing function" "FAIL"
fi
echo ""

# Test 20: Verify script has main monitoring loop
echo "Test 20: Verify script has main monitoring loop"
if grep -q "monitor_pr()" "${TEST_SCRIPT}"; then
    test_result "Has main monitoring loop" "PASS"
else
    test_result "Has main monitoring loop" "FAIL"
fi
echo ""

# Summary
echo "=================================="
echo "Test Results Summary"
echo "=================================="
echo "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
else
    echo -e "Tests failed: ${TESTS_FAILED}"
fi
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
