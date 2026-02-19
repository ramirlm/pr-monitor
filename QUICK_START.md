# PR Monitor Quick Start Guide

## Installation & Setup

```bash
# Option 1: Use npx (no installation required)
npx pr-monitor dashboard
# Opens at http://localhost:3000

# Option 2: Global install then use
npm install -g pr-monitor
pr-monitor dashboard

# Option 3: Manual setup (in .pr_monitor folder)
./pr-monitor.sh init
./pr-monitor.sh dashboard
```

## Basic Commands

### Start Monitoring a PR

```bash
# With npx
npx pr-monitor detect
npx pr-monitor start

# With global install
pr-monitor detect
pr-monitor start

# Manual installation
./pr-monitor.sh detect
./pr-monitor.sh start

# Specific PR number
pr-monitor start 4492
# or
./pr-monitor.sh start 4492

# With explicit repository
pr-monitor start 4492 g2i-ai/gheeggle
```

### View Errors

```bash
# With npx or global install
npx pr-monitor errors 4492
pr-monitor errors 4492

# Manual installation
./pr-monitor.sh errors 4492

# Auto-detect from current branch
pr-monitor errors

# Get errors as JSON (for AI agents)
curl http://localhost:3000/api/prs/4492/errors | jq
```

### Stop Monitoring

```bash
# With npx or global install
pr-monitor stop 4492

# Manual installation
./pr-monitor.sh stop 4492
```

### List Running Monitors

```bash
# With npx or global install  
pr-monitor list

# Manual installation
./pr-monitor.sh list
```

## Key Features

### 1. Detailed Workflow Tracking
- **All workflows** tracked with complete metadata
- **All jobs** within each workflow monitored
- **Failed steps** identified with timestamps
- **Direct links** to GitHub logs

### 2. Error Extraction
- Extracts specific error messages from failed jobs
- Provides structured JSON output
- Includes failed step details (name, number, duration)
- Groups errors by workflow

### 3. API Endpoints

```bash
# Workflow summary
curl http://localhost:3000/api/prs/4492/workflow-summary

# All workflows with job counts
curl http://localhost:3000/api/prs/4492/workflows

# Failed jobs only
curl http://localhost:3000/api/prs/4492/failed-jobs

# Detailed error information (for AI agents)
curl http://localhost:3000/api/prs/4492/errors
```

### 4. Dashboard Integration
- Visual monitoring of all PRs
- Real-time status updates every 30 seconds
- Start/stop monitors from UI
- Auto-detects PR from current branch

## Workflow Example

```bash
# 1. Create a PR or checkout branch with PR
git checkout feature/my-branch

# 2. Start monitoring (with npx - no installation needed)
npx pr-monitor start

# OR with global install
pr-monitor start

# OR with manual installation
./pr-monitor.sh start

# 3. View in dashboard (optional)
pr-monitor dashboard
# Visit http://localhost:3000

# 4. If CI fails, view errors
pr-monitor errors

# 5. Feed errors to AI for analysis
curl -s http://localhost:3000/api/prs/4492/errors | \
  jq '.failed_jobs' | \
  claude -p "Analyze these CI failures and suggest fixes"

# 6. Stop monitoring when done
pr-monitor stop
```

## AI Agent Integration

### Example: Automated Fix Suggestions

```bash
# Get error details as JSON
ERRORS=$(curl -s http://localhost:3000/api/prs/4492/errors)

# Send to Claude for analysis
echo "Analyze these GitHub Actions failures and provide specific fixes:

${ERRORS}

Please provide:
1. Root cause of each failure
2. Files that need to be modified
3. Specific code changes" | claude
```

### Example: Error Pattern Analysis

```bash
# Find common error patterns
./pr-monitor.sh errors 4492 | \
  jq -r '.failed_jobs[].error' | \
  sort | uniq -c | sort -rn
```

## Configuration

All configuration is auto-detected, but can be overridden:

```bash
# Set custom check interval (default: 60 seconds)
export CHECK_INTERVAL=30

# Set custom repository
export GITHUB_REPO="g2i-ai/gheeggle"

# Set custom GitHub token
export GITHUB_TOKEN="ghp_xxx"

# Then start monitoring
./pr-monitor.sh start 4492
```

## Troubleshooting

### Monitor not tracking workflows?

```bash
# Stop and restart to fetch latest data
./pr-monitor.sh stop 4492
./pr-monitor.sh start 4492

# Check logs
tail -f logs/pr_4492.log
```

### Database issues?

```bash
# Reinitialize (won't lose existing data)
./pr-monitor.sh init

# Query directly
sqlite3 data/pr_tracking.db "SELECT * FROM workflows LIMIT 5;"
```

### API not responding?

```bash
# Check dashboard is running
ps aux | grep "node.*server-simple"

# Restart dashboard
./pr-monitor.sh dashboard
```

## Files & Directories

```
.pr_monitor/
├── pr-monitor.sh              # Main CLI entry point
├── data/
│   ├── pr_tracking.db         # SQLite database
│   └── state/                 # Per-PR JSON state files
├── logs/                      # Log files (pr_<NUMBER>.log)
├── scripts/                   # Shell scripts
│   ├── check_pr_status.sh     # Main monitoring loop
│   ├── show_pr_errors.sh      # Error extraction
│   ├── extract_error_details.sh
│   └── utils.sh               # Shared utilities
└── dashboard/                 # Web dashboard
    ├── src/server-simple.ts   # Express API server
    └── public/                # Frontend files
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `npx pr-monitor init` or `pr-monitor init` | Initialize database |
| `npx pr-monitor detect` or `pr-monitor detect` | Detect PR from current branch |
| `npx pr-monitor start <PR>` or `pr-monitor start <PR>` | Start monitoring |
| `npx pr-monitor stop <PR>` or `pr-monitor stop <PR>` | Stop monitoring |
| `npx pr-monitor list` or `pr-monitor list` | List running monitors |
| `npx pr-monitor errors <PR>` or `pr-monitor errors <PR>` | Show detailed errors |
| `npx pr-monitor dashboard` or `pr-monitor dashboard` | Start web dashboard |
| `pr-monitor query list` | List all tracked PRs |

**Note:** Use `npx pr-monitor` to run without installing, or `pr-monitor` after global install with `npm install -g pr-monitor`.

## Documentation

- `README.md` - Full setup and usage guide
- `WORKFLOW_TRACKING.md` - Detailed workflow tracking docs
- `ERROR_EXTRACTION.md` - Error extraction and AI integration
- `CLAUDE.md` - Development guide for Claude Code

## Support

For issues or questions:
1. Check the log files in `logs/`
2. Query the database directly with sqlite3
3. Review the documentation files listed above
4. Check GitHub API rate limits: `gh api rate_limit`
