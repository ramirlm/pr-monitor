#!/usr/bin/env bash
#
# example_usage.sh
# Example of how to use check_pr_status.sh
#
# This script demonstrates the setup and usage of the PR monitoring tool

set -euo pipefail

cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║        GitHub PR Monitor - Example Usage                     ║
╚═══════════════════════════════════════════════════════════════╝

This script monitors GitHub Pull Requests for:
  • New comments (review and issue comments)
  • GitHub Actions workflow status changes
  • Pipeline failures with detailed error logs

Features:
  ✓ AI-powered analysis using Claude CLI
  ✓ Pushover notifications for all events
  ✓ Persistent state tracking to avoid duplicate alerts
  ✓ Automatic monitoring every 15 minutes (configurable)

════════════════════════════════════════════════════════════════

SETUP INSTRUCTIONS:

1. Get a GitHub Personal Access Token
   - Visit: https://github.com/settings/tokens
   - Generate new token with 'repo' scope
   - Save as: export GITHUB_TOKEN="ghp_xxxxxxxxxxxxx"

2. Set up Pushover (for notifications)
   - Create account: https://pushover.net/
   - Create an application to get API token
   - Note your user key
   - Save as: export PUSHOVER_USER="uxxxxxxxxxxxxx"
             export PUSHOVER_TOKEN="axxxxxxxxxxxxx"

3. (Optional) Install Claude CLI for AI analysis
   - Follow: https://docs.anthropic.com/
   - Without it, monitoring still works but without AI insights

4. Set repository
   - export GITHUB_REPO="owner/repo"
   - Example: export GITHUB_REPO="ramirlm/video-and-audio-handling"

════════════════════════════════════════════════════════════════

USAGE EXAMPLE:

# Set environment variables
export GITHUB_TOKEN="ghp_your_token_here"
export GITHUB_REPO="ramirlm/video-and-audio-handling"
export PUSHOVER_USER="your_user_key"
export PUSHOVER_TOKEN="your_app_token"

# Monitor PR #123 with default 15-minute intervals
./shell-scripts/check_pr_status.sh 123

# Or use custom interval (5 minutes)
CHECK_INTERVAL=300 ./shell-scripts/check_pr_status.sh 123

════════════════════════════════════════════════════════════════

WHAT HAPPENS:

The script will:
  1. Start monitoring PR #123
  2. Check every 15 minutes for:
     - New comments → Send notification with AI analysis
     - Failed workflows → Send notification with error details
     - Successful pipeline → Send success notification
  3. Log all activity to /tmp/pr_monitor_123.log
  4. Save state to /tmp/pr_monitor_state_123.json
  5. Continue until PR is closed or script is interrupted

════════════════════════════════════════════════════════════════

NOTIFICATIONS YOU'LL RECEIVE:

📱 "PR Monitor Started"
   - When monitoring begins

💬 "PR #123: New Comment"
   - When someone comments on the PR
   - Includes AI analysis of the comment

❌ "PR #123: Workflow Failed"
   - When a GitHub Actions workflow fails
   - Includes error details and AI-suggested fixes

✅ "PR #123: Pipeline Passed"
   - When all workflows complete successfully

🛑 "PR Monitor Stopped"
   - When PR is closed or monitoring stops

════════════════════════════════════════════════════════════════

TROUBLESHOOTING:

• Check logs: tail -f /tmp/pr_monitor_<PR_NUMBER>.log
• Check state: cat /tmp/pr_monitor_state_<PR_NUMBER>.json
• Verify tokens: echo $GITHUB_TOKEN (should not be empty)
• Test GitHub API: curl -H "Authorization: token $GITHUB_TOKEN" \
                       https://api.github.com/user

════════════════════════════════════════════════════════════════
EOF

echo ""
echo "Ready to start monitoring? Run:"
echo ""
echo "  ./shell-scripts/check_pr_status.sh <PR_NUMBER>"
echo ""
