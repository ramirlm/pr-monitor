# Pipeline Notifications with Pushover

The PR Monitor now sends real-time Pushover notifications when monitored PRs complete their pipeline execution (pass or fail).

## Features

### 1. **Pipeline-Level Notifications**
- Monitors the overall pipeline status (all GitHub Actions workflows)
- Sends **ONE notification** when the entire pipeline completes
- Prevents duplicate notifications during pipeline execution

### 2. **Status Tracking**
The system tracks four pipeline states:
- `no_workflows` - No workflows associated with the PR
- `in_progress` - One or more workflows are still running
- `success` - All workflows completed successfully
- `failed` - One or more workflows failed

### 3. **Smart Notification Logic**
- Notifications are sent only when pipeline status transitions to a terminal state (`success` or `failed`)
- Duplicate notifications are prevented using state tracking
- When pipeline status changes (e.g., new commit triggers new workflows), the notification flag is reset

### 4. **Notification Format**

**Success Notification:**
```
Title: PR #123: Add new feature
Message: ✅ Pipeline passed - all workflows completed successfully!
Priority: 0 (normal)
```

**Failure Notification:**
```
Title: PR #123: Add new feature  
Message: ❌ Pipeline failed - one or more workflows have failed.
Priority: 1 (high)
```

## Configuration

### 1. Get Pushover Credentials

1. Sign up at [pushover.net](https://pushover.net/)
2. Get your **User Key** from your dashboard
3. Create an application at [pushover.net/apps/build](https://pushover.net/apps/build)
4. Get your **API Token** from the application

### 2. Configure Environment Variables

Add to your `.env` file:

```bash
# Pushover Notifications (optional)
PUSHOVER_USER=your_user_key_here
PUSHOVER_TOKEN=your_api_token_here
```

### 3. Test the Configuration

Start monitoring a PR:
```bash
./pr-monitor.sh start 123
```

The monitor will send a startup notification if Pushover is configured correctly.

## How It Works

### Monitoring Loop

1. **Every CHECK_INTERVAL seconds** (default: 60), the monitor:
   - Fetches all workflows for the PR's HEAD commit
   - Determines the current pipeline status:
     - Are all workflows completed?
     - Did any workflow fail?
   - Compares with previous pipeline status
   - Sends notification if status changed to `success` or `failed`

### State Management

The monitor maintains state in `.pr_monitor/data/state/pr_<NUMBER>.json`:

```json
{
  "pipeline_status": "in_progress",
  "pipeline_notification_sent": false,
  "pipeline_passed": false,
  ...
}
```

- `pipeline_status` - Current pipeline state
- `pipeline_notification_sent` - Whether notification was sent for current status
- `pipeline_passed` - Legacy flag for backward compatibility

### Notification Timing

**Scenario 1: All workflows pass**
1. Initial check: 3 workflows running → Status: `in_progress` → No notification
2. Second check: 3 workflows complete, all success → Status: `success` → **Send notification**
3. Third check: Same status → Status: `success` → No notification (duplicate prevention)

**Scenario 2: One workflow fails**
1. Initial check: 3 workflows running → Status: `in_progress` → No notification
2. Second check: 2 complete (success), 1 running → Status: `in_progress` → No notification
3. Third check: 3 complete, 1 failed → Status: `failed` → **Send notification**
4. Fourth check: Same status → Status: `failed` → No notification (duplicate prevention)

**Scenario 3: New commit (status cycle)**
1. Previous: Pipeline was `success`, notification sent
2. New commit triggers new workflows → Status: `in_progress` → Reset notification flag
3. Workflows complete successfully → Status: `success` → **Send notification** (new cycle)

## Testing

### Unit Tests

Run the test suite to verify notification logic:
```bash
bash scripts/test_pipeline_notifications.sh
```

This tests:
- Pipeline status determination
- Notification triggering logic
- Duplicate prevention
- Status transition handling

### Manual Testing

1. Start monitoring a PR with active workflows:
   ```bash
   ./pr-monitor.sh start 123
   ```

2. Watch the logs:
   ```bash
   tail -f logs/pr_123.log
   ```

3. Look for pipeline status messages:
   ```
   Pipeline status: in_progress -> success
   Pipeline passed - sending success notification
   ```

4. Check your Pushover app for the notification

## Troubleshooting

### No Notifications Received

1. **Check Pushover is enabled:**
   ```bash
   # View current monitor logs
   tail -f logs/pr_*.log | grep -i pushover
   ```
   
   Should see: "Sending Pushover notification: ..."
   Not: "Pushover disabled, skipping notification: ..."

2. **Verify credentials:**
   ```bash
   # Check environment variables are set
   echo $PUSHOVER_USER
   echo $PUSHOVER_TOKEN
   ```

3. **Test Pushover directly:**
   ```bash
   curl -s -X POST https://api.pushover.net/1/messages.json \
     -d "token=${PUSHOVER_TOKEN}" \
     -d "user=${PUSHOVER_USER}" \
     -d "title=Test" \
     -d "message=Testing Pushover"
   ```

### Multiple Notifications

If you're receiving multiple notifications for the same pipeline:

1. **Check state file:**
   ```bash
   cat data/state/pr_123.json | jq '{pipeline_status, pipeline_notification_sent}'
   ```

2. **Verify only one monitor is running:**
   ```bash
   ps aux | grep check_pr_status.sh
   ```

3. **Stop all monitors and restart:**
   ```bash
   pkill -f check_pr_status.sh
   ./pr-monitor.sh start 123
   ```

### Notifications Sent Too Early

If notifications are sent before all workflows complete:

1. Check the workflow fetch logic - ensure all workflows for the HEAD commit are fetched
2. Verify the `all_completed` flag is working correctly
3. Check logs for "Workflow ... (ID): in_progress" messages

## API Integration

The notification logic is integrated into the main monitoring script (`scripts/check_pr_status.sh`).

Key functions:
- `send_pushover_notification()` - Sends notification via Pushover API
- `process_workflow_runs()` - Determines pipeline status and triggers notifications
- `initialize_state()` - Sets up state tracking with notification flags

## Backward Compatibility

The implementation maintains backward compatibility:
- Old state files without `pipeline_status` fields will initialize with defaults
- The `pipeline_passed` boolean flag is still updated for legacy code
- Pushover is optional - monitor works without it (just skips notifications)

## Related Documentation

- [Workflow Tracking](WORKFLOW_TRACKING.md) - Details on workflow/job tracking
- [Duplicate Prevention](DUPLICATE_PREVENTION.md) - General duplicate prevention strategy
- [README](README.md) - Main project documentation
