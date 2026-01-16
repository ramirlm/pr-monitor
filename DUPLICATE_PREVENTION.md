# Duplicate Monitor Prevention

## The Problem

When starting a monitor for a PR, the system was allowing multiple monitors to be created for the same PR. This happened because:

1. **CLI had no duplicate check** - The `./pr-monitor.sh start` command didn't check if a monitor was already running before starting a new one
2. **Dashboard race condition** - Clicking "Start Monitoring" multiple times quickly before the first process started would spawn multiple monitors
3. **No cleanup mechanism** - There was no easy way to find and stop duplicate monitors

## The Fix

### 1. CLI Duplicate Prevention

The CLI now checks for existing monitors before starting:

```bash
./pr-monitor.sh start 4492
```

If a monitor is already running:
```
⚠️  Monitor is already running for PR #4492

Running monitors:
  PID: 75860 - Running: 0:00.03

To stop existing monitors: ./pr-monitor.sh stop 4492
To force start anyway, first stop the existing monitor
```

### 2. Enhanced Stop Command

The stop command now:
- Finds ALL monitors for a PR (not just one)
- Reports how many it's stopping
- Force kills any that don't stop gracefully
- Verifies all are stopped

```bash
./pr-monitor.sh stop 4492
# Output: ✅ Stopped 3 monitor(s) for PR #4492
```

### 3. Dashboard Button Protection

The dashboard now prevents rapid-clicking:

- **Button disabling**: When you click "Start Monitoring", the button immediately disables and shows "⏳ Starting..."
- **Tracking set**: A `monitorsBeingStarted` Set prevents multiple simultaneous requests
- **Better error messages**: Clear alerts when a monitor is already running
- **Auto-refresh**: Banner updates to show "Already Monitoring" state

### 4. Cleanup Command

New command to find and remove all duplicate monitors:

```bash
./pr-monitor.sh cleanup
```

This will:
- Scan all running monitors
- Find PRs with multiple monitors
- Stop all duplicates (keeping only the oldest one)
- Report what was cleaned up

## How to Use

### Check for Duplicates

```bash
./pr-monitor.sh list
```

This shows all running monitors with their PIDs.

### Clean Up Duplicates

```bash
./pr-monitor.sh cleanup
```

Example output:
```
🔍 Checking for duplicate monitors...

⚠️  PR #4492 has 3 monitors running:
   PID: 75860
   PID: 76123
   PID: 76456

   Stopping duplicate monitors...
   ✅ Stopped PID 76123
   ✅ Stopped PID 76456

✅ Cleanup complete

Remaining monitors:
  PR #4492 - PID: 75860 - Running: 0:05.23
```

### Prevent Duplicates When Starting

**Via CLI:**
```bash
# This will now check for duplicates first
./pr-monitor.sh start 4492
```

**Via Dashboard:**
- Click "Start Monitoring" once
- Wait for the button to change to "Already Monitoring"
- The system prevents you from clicking multiple times

## Testing

### Verify No Duplicates Exist

```bash
./pr-monitor.sh list
# Should show only ONE monitor per PR
```

### Try Starting a Duplicate

```bash
# Start a monitor
./pr-monitor.sh start 4492

# Try starting again - should be prevented
./pr-monitor.sh start 4492
# Output: ⚠️  Monitor is already running for PR #4492
```

### Test Cleanup

```bash
# If you somehow have duplicates (e.g., started via different methods)
./pr-monitor.sh cleanup
# Should remove all but one monitor per PR
```

## Why Duplicates Happened

Based on the fixes, here's what likely caused your 3 monitors:

### Scenario 1: Rapid Dashboard Clicks
- You clicked "Start Monitoring" quickly 2-3 times
- Before the first process started, all 3 clicks passed the duplicate check
- Result: 3 monitors spawned

### Scenario 2: Mixed CLI + Dashboard
- Started one via CLI: `./pr-monitor.sh start 4492`
- Then clicked "Start Monitoring" in dashboard twice
- Result: 3 monitors

### Scenario 3: Old Processes
- Had a monitor running from a previous session
- Started a new one via CLI
- Started another via dashboard
- Result: 3 monitors

## Prevention Going Forward

With the fixes in place:

1. **CLI prevents duplicates** - Won't start if one exists
2. **Dashboard prevents race conditions** - Button disables immediately
3. **Easy cleanup** - `./pr-monitor.sh cleanup` removes extras
4. **Better visibility** - `./pr-monitor.sh list` shows all monitors
5. **Enhanced stop** - Stops ALL monitors for a PR, not just one

## Troubleshooting

### Still seeing duplicates?

```bash
# List all monitors
./pr-monitor.sh list

# Clean them up
./pr-monitor.sh cleanup

# Or manually stop specific PR
./pr-monitor.sh stop 4492
```

### Monitor won't stop?

```bash
# Find the PID
ps aux | grep "check_pr_status.sh 4492"

# Force kill
kill -9 <PID>
```

### Dashboard shows "Already Monitoring" but CLI shows none?

```bash
# Restart dashboard to sync state
# Press Ctrl+C in dashboard terminal
./pr-monitor.sh dashboard
```

## Summary

The duplicate monitor issue is now **completely prevented** through:
- ✅ CLI duplicate checks
- ✅ Dashboard race condition protection
- ✅ Enhanced stop command (stops all duplicates)
- ✅ New cleanup command
- ✅ Better error messages and visibility

You should never see 3 monitors for one PR again!
