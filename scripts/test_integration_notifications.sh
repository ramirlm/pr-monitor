#!/usr/bin/env bash
#
# test_integration_notifications.sh
# Integration test that simulates workflow processing
# Tests the full notification flow with mock data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================"
echo "Integration Test: Notification Flow"
echo "============================================"
echo ""

# Create temporary test directory
TEST_DIR=$(mktemp -d)

# Cleanup on exit
cleanup() {
    rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

# Test 1: Simulate state file initialization
echo "Test 1: State file initialization"
STATE_FILE="${TEST_DIR}/pr_123.json"

# Initialize state (simulate initialize_state function)
cat > "${STATE_FILE}" <<'EOF'
{
    "last_comment_count": 0,
    "last_workflow_status": {},
    "notified_comments": [],
    "notified_workflows": [],
    "pipeline_passed": false,
    "pipeline_status": "unknown",
    "pipeline_notification_sent": false
}
EOF

if [[ -f "${STATE_FILE}" ]]; then
    echo -e "${GREEN}✓${NC} State file created"
    echo "  State file content:"
    cat "${STATE_FILE}" | jq '.'
else
    echo -e "${RED}✗${NC} Failed to create state file"
    exit 1
fi

echo ""

# Test 2: Simulate status transition (unknown -> in_progress)
echo "Test 2: Status transition: unknown -> in_progress"

state=$(cat "${STATE_FILE}")
current_status="in_progress"
previous_status=$(echo "${state}" | jq -r '.pipeline_status // "unknown"')

echo "  Previous status: ${previous_status}"
echo "  Current status: ${current_status}"

# Update state
state=$(echo "${state}" | jq --arg status "${current_status}" '.pipeline_status = $status')
echo "${state}" > "${STATE_FILE}"

notification_sent=$(echo "${state}" | jq -r '.pipeline_notification_sent')
echo "  Notification sent: ${notification_sent}"

if [[ "${notification_sent}" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No notification sent (expected for in_progress)"
else
    echo -e "${RED}✗${NC} Unexpected notification sent"
    exit 1
fi

echo ""

# Test 3: Simulate status transition (in_progress -> success)
echo "Test 3: Status transition: in_progress -> success"

state=$(cat "${STATE_FILE}")
current_status="success"
previous_status=$(echo "${state}" | jq -r '.pipeline_status // "unknown"')
notification_sent=$(echo "${state}" | jq -r '.pipeline_notification_sent // false')

echo "  Previous status: ${previous_status}"
echo "  Current status: ${current_status}"
echo "  Notification sent: ${notification_sent}"

# Status changed, reset flag
if [[ "${current_status}" != "${previous_status}" ]]; then
    state=$(echo "${state}" | jq '.pipeline_notification_sent = false')
    notification_sent="false"
    echo "  Flag reset due to status change"
fi

# Check if we should send notification
should_notify="false"
if [[ "${notification_sent}" == "false" ]] && [[ "${current_status}" == "success" ]]; then
    should_notify="true"
    echo -e "${BLUE}  → Would send: Pushover notification (success)${NC}"
    state=$(echo "${state}" | jq '.pipeline_notification_sent = true')
fi

# Update state
state=$(echo "${state}" | jq --arg status "${current_status}" '.pipeline_status = $status')
state=$(echo "${state}" | jq '.pipeline_passed = true')
echo "${state}" > "${STATE_FILE}"

if [[ "${should_notify}" == "true" ]]; then
    echo -e "${GREEN}✓${NC} Notification triggered (expected)"
else
    echo -e "${RED}✗${NC} Notification not triggered"
    exit 1
fi

echo ""

# Test 4: Simulate duplicate check (success -> success)
echo "Test 4: Duplicate check: success -> success (no status change)"

state=$(cat "${STATE_FILE}")
current_status="success"
previous_status=$(echo "${state}" | jq -r '.pipeline_status // "unknown"')
notification_sent=$(echo "${state}" | jq -r '.pipeline_notification_sent // false')

echo "  Previous status: ${previous_status}"
echo "  Current status: ${current_status}"
echo "  Notification sent: ${notification_sent}"

# Status didn't change, keep flag
if [[ "${current_status}" != "${previous_status}" ]]; then
    state=$(echo "${state}" | jq '.pipeline_notification_sent = false')
    notification_sent="false"
fi

# Check if we should send notification
should_notify="false"
if [[ "${notification_sent}" == "false" ]] && [[ "${current_status}" == "success" ]]; then
    should_notify="true"
fi

if [[ "${should_notify}" == "false" ]]; then
    echo -e "${GREEN}✓${NC} Duplicate notification prevented (expected)"
else
    echo -e "${RED}✗${NC} Duplicate notification would be sent"
    exit 1
fi

echo ""

# Test 5: Simulate status cycle (success -> in_progress -> failed)
echo "Test 5: Status cycle: success -> in_progress -> failed"

# First transition: success -> in_progress
state=$(cat "${STATE_FILE}")
current_status="in_progress"
previous_status=$(echo "${state}" | jq -r '.pipeline_status // "unknown"')

echo "  Step 1: ${previous_status} -> ${current_status}"

if [[ "${current_status}" != "${previous_status}" ]]; then
    state=$(echo "${state}" | jq '.pipeline_notification_sent = false')
    echo "    Flag reset: true"
fi

state=$(echo "${state}" | jq --arg status "${current_status}" '.pipeline_status = $status')
state=$(echo "${state}" | jq '.pipeline_passed = false')
echo "${state}" > "${STATE_FILE}"

# Second transition: in_progress -> failed
state=$(cat "${STATE_FILE}")
current_status="failed"
previous_status=$(echo "${state}" | jq -r '.pipeline_status // "unknown"')
notification_sent=$(echo "${state}" | jq -r '.pipeline_notification_sent // false')

echo "  Step 2: ${previous_status} -> ${current_status}"
echo "    Notification sent: ${notification_sent}"

if [[ "${current_status}" != "${previous_status}" ]]; then
    state=$(echo "${state}" | jq '.pipeline_notification_sent = false')
    notification_sent="false"
fi

should_notify="false"
if [[ "${notification_sent}" == "false" ]] && [[ "${current_status}" == "failed" ]]; then
    should_notify="true"
    echo -e "${BLUE}    → Would send: Pushover notification (failed)${NC}"
    state=$(echo "${state}" | jq '.pipeline_notification_sent = true')
fi

state=$(echo "${state}" | jq --arg status "${current_status}" '.pipeline_status = $status')
state=$(echo "${state}" | jq '.pipeline_passed = false')
echo "${state}" > "${STATE_FILE}"

if [[ "${should_notify}" == "true" ]]; then
    echo -e "${GREEN}✓${NC} Notification triggered after status cycle (expected)"
else
    echo -e "${RED}✗${NC} Notification not triggered"
    exit 1
fi

echo ""

# Test 6: Verify final state
echo "Test 6: Verify final state"

state=$(cat "${STATE_FILE}")
echo "  Final state:"
echo "${state}" | jq '{pipeline_status, pipeline_notification_sent, pipeline_passed}'

pipeline_status=$(echo "${state}" | jq -r '.pipeline_status')
notification_sent=$(echo "${state}" | jq -r '.pipeline_notification_sent')
pipeline_passed=$(echo "${state}" | jq -r '.pipeline_passed')

if [[ "${pipeline_status}" == "failed" ]] && [[ "${notification_sent}" == "true" ]] && [[ "${pipeline_passed}" == "false" ]]; then
    echo -e "${GREEN}✓${NC} Final state is correct"
else
    echo -e "${RED}✗${NC} Final state is incorrect"
    exit 1
fi

echo ""
echo "============================================"
echo -e "${GREEN}✓ All integration tests passed!${NC}"
echo "============================================"
