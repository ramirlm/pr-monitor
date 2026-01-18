# Example: Pipeline Notification Flow

This document shows example log output demonstrating the pipeline notification feature in action.

## Scenario 1: Successful Pipeline

### Initial Check (Workflows Running)
```
2024-01-18 17:45:00 [INFO] === Check iteration 1 at Thu Jan 18 17:45:00 UTC 2024 ===
2024-01-18 17:45:00 [INFO] Fetching PR details...
2024-01-18 17:45:00 [INFO] PR State: open
2024-01-18 17:45:00 [INFO] Fetching workflow runs...
2024-01-18 17:45:01 [INFO] Workflow 'CI' (12345678): in_progress - 
2024-01-18 17:45:01 [INFO]   Jobs: 5 total, 0 failed
2024-01-18 17:45:01 [INFO] Workflow 'Tests' (12345679): in_progress - 
2024-01-18 17:45:01 [INFO]   Jobs: 3 total, 0 failed
2024-01-18 17:45:01 [INFO] Workflow 'Lint' (12345680): completed - success
2024-01-18 17:45:01 [INFO]   Jobs: 2 total, 0 failed
2024-01-18 17:45:01 [INFO] Pipeline status: unknown -> in_progress
2024-01-18 17:45:01 [INFO] Check complete. Sleeping for 60s
```

**No notification sent** - Pipeline is still in progress.

---

### Second Check (All Workflows Complete)
```
2024-01-18 17:46:01 [INFO] === Check iteration 2 at Thu Jan 18 17:46:01 UTC 2024 ===
2024-01-18 17:46:01 [INFO] Fetching PR details...
2024-01-18 17:46:01 [INFO] PR State: open
2024-01-18 17:46:01 [INFO] Fetching workflow runs...
2024-01-18 17:46:02 [INFO] Workflow 'CI' (12345678): completed - success
2024-01-18 17:46:02 [INFO] CI passed (5 jobs)
2024-01-18 17:46:02 [INFO]   Jobs: 5 total, 0 failed
2024-01-18 17:46:02 [INFO] Workflow 'Tests' (12345679): completed - success
2024-01-18 17:46:02 [INFO] Tests passed (3 jobs)
2024-01-18 17:46:02 [INFO]   Jobs: 3 total, 0 failed
2024-01-18 17:46:02 [INFO] Workflow 'Lint' (12345680): completed - success
2024-01-18 17:46:02 [INFO] Lint passed (2 jobs)
2024-01-18 17:46:02 [INFO]   Jobs: 2 total, 0 failed
2024-01-18 17:46:02 [INFO] Pipeline status: in_progress -> success
2024-01-18 17:46:02 [INFO] Pipeline passed - sending success notification
2024-01-18 17:46:02 [INFO] Sending Pushover notification: PR #123: Add new feature
2024-01-18 17:46:03 [INFO] Pushover notification sent successfully
2024-01-18 17:46:03 [INFO] Check complete. Sleeping for 60s
```

**✅ Notification sent:**
- **Title:** "PR #123: Add new feature"
- **Message:** "✅ Pipeline passed - all workflows completed successfully!"
- **Priority:** 0 (normal)

---

### Third Check (No Change)
```
2024-01-18 17:47:03 [INFO] === Check iteration 3 at Thu Jan 18 17:47:03 UTC 2024 ===
2024-01-18 17:47:03 [INFO] Fetching PR details...
2024-01-18 17:47:03 [INFO] PR State: open
2024-01-18 17:47:03 [INFO] Fetching workflow runs...
2024-01-18 17:47:04 [INFO] Workflow 'CI' (12345678): completed - success
2024-01-18 17:47:04 [INFO] CI passed (5 jobs)
2024-01-18 17:47:04 [INFO]   Jobs: 5 total, 0 failed
2024-01-18 17:47:04 [INFO] Workflow 'Tests' (12345679): completed - success
2024-01-18 17:47:04 [INFO] Tests passed (3 jobs)
2024-01-18 17:47:04 [INFO]   Jobs: 3 total, 0 failed
2024-01-18 17:47:04 [INFO] Workflow 'Lint' (12345680): completed - success
2024-01-18 17:47:04 [INFO] Lint passed (2 jobs)
2024-01-18 17:47:04 [INFO]   Jobs: 2 total, 0 failed
2024-01-18 17:47:04 [INFO] Pipeline status: success -> success
2024-01-18 17:47:04 [INFO] Check complete. Sleeping for 60s
```

**No notification sent** - Duplicate prevention in action. Pipeline status unchanged.

---

## Scenario 2: Failed Pipeline

### Initial Check (Workflows Running)
```
2024-01-18 18:00:00 [INFO] === Check iteration 1 at Thu Jan 18 18:00:00 UTC 2024 ===
2024-01-18 18:00:00 [INFO] Fetching PR details...
2024-01-18 18:00:00 [INFO] PR State: open
2024-01-18 18:00:00 [INFO] Fetching workflow runs...
2024-01-18 18:00:01 [INFO] Workflow 'CI' (23456789): in_progress - 
2024-01-18 18:00:01 [INFO]   Jobs: 5 total, 0 failed
2024-01-18 18:00:01 [INFO] Workflow 'Tests' (23456790): in_progress - 
2024-01-18 18:00:01 [INFO]   Jobs: 3 total, 0 failed
2024-01-18 18:00:01 [INFO] Pipeline status: unknown -> in_progress
2024-01-18 18:00:01 [INFO] Check complete. Sleeping for 60s
```

**No notification sent** - Pipeline is still in progress.

---

### Second Check (Failure Detected)
```
2024-01-18 18:01:01 [INFO] === Check iteration 2 at Thu Jan 18 18:01:01 UTC 2024 ===
2024-01-18 18:01:01 [INFO] Fetching PR details...
2024-01-18 18:01:01 [INFO] PR State: open
2024-01-18 18:01:01 [INFO] Fetching workflow runs...
2024-01-18 18:01:02 [INFO] Workflow 'CI' (23456789): completed - failure
2024-01-18 18:01:02 [ERROR] Workflow 'CI' failed!
2024-01-18 18:01:02 [INFO]   Jobs: 5 total, 2 failed
2024-01-18 18:01:02 [INFO] Workflow 'Tests' (23456790): completed - success
2024-01-18 18:01:02 [INFO] Tests passed (3 jobs)
2024-01-18 18:01:02 [INFO]   Jobs: 3 total, 0 failed
2024-01-18 18:01:02 [INFO] Pipeline status: in_progress -> failed
2024-01-18 18:01:02 [INFO] Pipeline failed - sending failure notification
2024-01-18 18:01:02 [INFO] Sending Pushover notification: PR #124: Fix bug
2024-01-18 18:01:03 [INFO] Pushover notification sent successfully
2024-01-18 18:01:03 [INFO] Check complete. Sleeping for 60s
```

**❌ Notification sent:**
- **Title:** "PR #124: Fix bug"
- **Message:** "❌ Pipeline failed - one or more workflows have failed."
- **Priority:** 1 (high)

---

## Scenario 3: Status Cycle (New Commit)

### Initial State (Previous Pipeline Failed)
```
State file: pipeline_status="failed", pipeline_notification_sent=true
```

---

### New Commit Pushed
```
2024-01-18 18:15:00 [INFO] === Check iteration 5 at Thu Jan 18 18:15:00 UTC 2024 ===
2024-01-18 18:15:00 [INFO] Fetching PR details...
2024-01-18 18:15:00 [INFO] PR State: open
2024-01-18 18:15:00 [INFO] Fetching workflow runs...
2024-01-18 18:15:01 [INFO] Workflow 'CI' (34567890): queued - 
2024-01-18 18:15:01 [INFO]   Jobs: 0 total, 0 failed
2024-01-18 18:15:01 [INFO] Workflow 'Tests' (34567891): in_progress - 
2024-01-18 18:15:01 [INFO]   Jobs: 1 total, 0 failed
2024-01-18 18:15:01 [INFO] Pipeline status: failed -> in_progress
2024-01-18 18:15:01 [INFO] Check complete. Sleeping for 60s
```

**No notification sent** - Status changed to in_progress, but notification flag was reset.

---

### Workflows Complete (Success)
```
2024-01-18 18:18:00 [INFO] === Check iteration 8 at Thu Jan 18 18:18:00 UTC 2024 ===
2024-01-18 18:18:00 [INFO] Fetching PR details...
2024-01-18 18:18:00 [INFO] PR State: open
2024-01-18 18:18:00 [INFO] Fetching workflow runs...
2024-01-18 18:18:01 [INFO] Workflow 'CI' (34567890): completed - success
2024-01-18 18:18:01 [INFO] CI passed (5 jobs)
2024-01-18 18:18:01 [INFO]   Jobs: 5 total, 0 failed
2024-01-18 18:18:01 [INFO] Workflow 'Tests' (34567891): completed - success
2024-01-18 18:18:01 [INFO] Tests passed (3 jobs)
2024-01-18 18:18:01 [INFO]   Jobs: 3 total, 0 failed
2024-01-18 18:18:01 [INFO] Pipeline status: in_progress -> success
2024-01-18 18:18:01 [INFO] Pipeline passed - sending success notification
2024-01-18 18:18:01 [INFO] Sending Pushover notification: PR #124: Fix bug
2024-01-18 18:18:02 [INFO] Pushover notification sent successfully
2024-01-18 18:18:02 [INFO] Check complete. Sleeping for 60s
```

**✅ Notification sent:**
- **Title:** "PR #124: Fix bug"
- **Message:** "✅ Pipeline passed - all workflows completed successfully!"
- **Priority:** 0 (normal)

The notification flag was reset when status changed from `failed` to `in_progress`, so a new notification is sent when it completes successfully.

---

## Key Observations

1. **Single Notification Per Completion**: Only one notification is sent when the pipeline reaches a terminal state (success or failure).

2. **Duplicate Prevention**: Subsequent checks with the same pipeline status do not trigger new notifications.

3. **Status Cycles**: When the pipeline status changes (e.g., new commit), the notification flag is reset, allowing a new notification when the new pipeline completes.

4. **PR Title Included**: The notification title always includes the PR number and title as specified in requirements.

5. **Priority Levels**:
   - Success: Priority 0 (normal)
   - Failure: Priority 1 (high)

6. **No Intermediate Notifications**: The system does not send notifications for individual workflow failures or while workflows are in progress. Only the final pipeline state triggers a notification.
