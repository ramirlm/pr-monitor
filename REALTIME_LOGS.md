# Real-Time Log Viewer

The PR Monitor Dashboard now includes a real-time log viewer that shows you exactly what's being fetched and processed for each monitored PR.

## Features

### Live Log Streaming
- **Real-time updates** every 3 seconds (configurable)
- **Color-coded log levels** for easy scanning:
  - 🔴 **[ERROR]** - Red, bold
  - 🟡 **[WARN]** - Yellow, bold
  - 🔵 **[INFO]** - Blue
  - ⚪ **[DEBUG]** - Gray
  - ✅ Success indicators - Green
  - ❌ Error indicators - Red

### Terminal-Style Display
- **Dark theme** with monospace font
- **Auto-scroll** to latest logs
- **Syntax highlighting** for common patterns
- **400px height** with scrollable content
- Shows last **100 lines** by default

### Controls
- **PR Selector** - Dropdown to choose which PR's logs to view
- **Auto-refresh toggle** - Enable/disable automatic updates
- **Manual refresh button** - Force reload logs on demand
- **Clear button** - Clear the display

## How to Use

### Via Dashboard

1. **Start the dashboard:**
   ```bash
   ./pr-monitor.sh dashboard
   ```

2. **Open in browser:** http://localhost:3000

3. **Navigate to "Running Monitors" tab**

4. **View logs:**
   - Select a PR from the dropdown below the monitors list
   - Logs will appear immediately in the dark terminal-style viewer
   - Auto-refresh is ON by default (updates every 3 seconds)

### What You'll See

The log viewer shows exactly what the monitor is doing:

```
2024-01-15 10:30:00 [INFO] Starting PR #4492 monitoring (interval: 60s)
2024-01-15 10:30:00 [INFO] Repository: g2i-ai/gheeggle
2024-01-15 10:30:00 [INFO] === Check iteration 1 at Mon Jan 15 10:30:00 PST 2024 ===
2024-01-15 10:30:01 [INFO] Fetching PR details...
2024-01-15 10:30:02 [INFO] PR State: open
2024-01-15 10:30:02 [INFO] Fetching PR comments...
2024-01-15 10:30:03 [INFO] Fetching workflow runs...
2024-01-15 10:30:04 [INFO] Workflow 'CI' (123456): completed - success
2024-01-15 10:30:04 [INFO]   Jobs: 10 total, 0 failed
2024-01-15 10:30:04 [INFO] ✓ Workflow 'CI' passed (10 jobs)
2024-01-15 10:30:04 [INFO] Check complete. Sleeping for 60s
```

### Log Levels Explained

- **[INFO]** - Normal operations (fetching data, processing workflows)
- **[WARN]** - Warnings (rate limits approaching, retries)
- **[ERROR]** - Errors (API failures, database issues)
- **[DEBUG]** - Detailed debugging information

### Auto-Refresh

The log viewer auto-refreshes every **3 seconds** by default:

- Check the "Auto-refresh" checkbox to enable/disable
- When enabled, you'll see a 🟢 Live indicator in the metadata bar
- Logs automatically scroll to the bottom with each update
- Your PR selection is preserved during refreshes

## API Endpoints

### Get Last N Lines
```bash
GET /api/logs/:prNumber/tail?lines=100
```

**Response:**
```json
{
  "success": true,
  "logs": "2024-01-15 10:30:00 [INFO] Starting PR #4492...",
  "exists": true,
  "timestamp": "2024-01-15T18:30:05.123Z"
}
```

### Get Full Log with Metadata
```bash
GET /api/logs/:prNumber?lines=200&offset=0
```

**Response:**
```json
{
  "success": true,
  "logs": "...",
  "exists": true,
  "metadata": {
    "total_lines": 1234,
    "file_size_bytes": 45678,
    "lines_returned": 200,
    "log_path": "/path/to/pr_4492.log"
  }
}
```

## CLI Access

You can also view logs via command line:

```bash
# View last 50 lines
tail -f logs/pr_4492.log

# View last 100 lines
tail -n 100 logs/pr_4492.log

# Follow in real-time
tail -f logs/pr_4492.log

# Search for errors
grep ERROR logs/pr_4492.log

# Count workflow checks
grep "Fetching workflow runs" logs/pr_4492.log | wc -l
```

## What Gets Logged

### Monitor Startup
- PR number, repository, check interval
- Initial notifications sent
- Database initialization

### Each Check Iteration
- Iteration number and timestamp
- Fetching PR details
- Current PR state
- Comment fetching and counts
- Workflow run fetching
- Individual workflow status (with job counts)
- Failed job details (if any)
- Check completion time

### New Events
- New comments detected
- Workflow failures (with AI analysis trigger)
- Workflow successes
- Pipeline passes
- PR state changes (open → closed)

### Errors and Warnings
- API failures
- Database errors
- Rate limiting warnings
- Notification failures

## Customization

### Change Refresh Interval

Modify in `dashboard/public/app.js`:

```javascript
logRefreshInterval = setInterval(() => {
    if (currentLogPR) {
        loadLogs(currentLogPR);
    }
}, 3000); // Change to 5000 for 5 seconds, etc.
```

### Change Number of Lines

Modify the `loadLogs` function call:

```javascript
loadLogs(prNumber, 150); // Show 150 lines instead of 100
```

### Change Display Height

Modify in `index.html`:

```html
<div id="log-display" ... style="height: 600px; ...">
```

## Troubleshooting

### No logs showing?

**Check if monitor is running:**
```bash
./pr-monitor.sh list
```

**Check if log file exists:**
```bash
ls -la logs/pr_4492.log
```

**Try manually viewing:**
```bash
tail logs/pr_4492.log
```

### Logs not updating?

**Check auto-refresh is enabled:**
- Look for checked checkbox in dashboard
- Look for 🟢 Live indicator

**Manually refresh:**
- Click the 🔄 Refresh button

### "Waiting for monitor to start..."?

This means:
- Monitor hasn't started yet
- Monitor is starting but hasn't written logs yet
- Log file path is incorrect

**Solution:**
Wait a few seconds or check monitor status:
```bash
./pr-monitor.sh list
```

### Logs showing errors?

**Common errors and solutions:**

1. **"Permission denied"**
   - Check file permissions on logs directory
   - Run: `chmod +x logs/`

2. **"No such file"**
   - Monitor hasn't started
   - Start monitor: `./pr-monitor.sh start 4492`

3. **"Failed to fetch"**
   - Dashboard not running
   - Restart: `./pr-monitor.sh dashboard`

## Performance

### Memory Usage
- Log viewer fetches only last N lines (default: 100)
- Old logs are not kept in browser memory
- Each fetch is ~1-5KB typically

### Network Usage
- API call every 3 seconds when auto-refresh enabled
- ~500 bytes per request
- Minimal bandwidth (~10KB/minute)

### Log File Size
- Logs rotate automatically (managed by the shell script)
- Typical size: 100KB - 1MB per PR
- Stored in `logs/` directory

## Benefits

### For Developers
- **Instant visibility** into what the monitor is doing
- **Debug issues** without SSH or terminal access
- **Verify monitors are working** at a glance
- **See API calls** being made in real-time

### For Monitoring
- **Confirm data fetching** is happening
- **Spot patterns** in workflow checks
- **Identify rate limiting** before it's a problem
- **Verify error handling** is working

### For Debugging
- **See exact API responses** in context
- **Track down** when workflows were checked
- **Identify** what triggered notifications
- **Understand** monitor behavior over time

## Future Enhancements

Potential additions:
- Search/filter logs in UI
- Download logs as file
- Multiple PR log comparison
- Log level filtering (show only errors)
- Tail mode (continuous scroll)
- Historical log viewing
- Log export to JSON

## Summary

The real-time log viewer gives you complete visibility into what your PR monitors are doing, with:

✅ Live updates every 3 seconds
✅ Color-coded log levels
✅ Terminal-style display
✅ Easy PR selection
✅ Auto-scroll to latest
✅ Manual refresh control
✅ API and CLI access

Now you can see exactly what's being fetched and processed for each PR in real-time!
