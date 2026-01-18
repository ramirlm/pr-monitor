# PR Monitor - Portable GitHub PR Monitoring System

A self-contained, portable system for monitoring GitHub Pull Requests with automated Claude CLI assistance.

## Features

- 🔍 **Auto-detection**: Automatically detects PR for current Git branch
- 🚀 **Manual trigger**: Start monitoring from web dashboard
- 📊 **Real-time tracking**: Monitor CI checks, reviews, and comments
- 🔔 **Push notifications**: Pushover notifications for pipeline completion
- 🤖 **Claude integration**: Automated assistance via Claude CLI
- 🗃️ **Local storage**: Repository-specific SQLite database
- 📦 **Portable**: Drop into any Git repository

## Quick Start

### 1. Prerequisites

- Git repository with GitHub remote
- [GitHub CLI](https://cli.github.com/) installed and authenticated: `gh auth login`
- [Claude CLI](https://docs.anthropic.com/claude/docs/claude-cli) installed (optional, for automation)
- Node.js 18+ (for web dashboard)

### 2. Setup

```bash
# Copy configuration template
cp .pr_monitor/.env.example .pr_monitor/.env

# Edit .env if needed (auto-detection works in most cases)
# GITHUB_TOKEN and GITHUB_REPO are auto-detected from gh CLI and git

# Initialize database
bash .pr_monitor/scripts/init_pr_db.sh
```

### 3. Usage

#### Option A: Web Dashboard (Recommended)

```bash
# Start the dashboard
bash .pr_monitor/pr-monitor.sh dashboard

# Open http://localhost:3000
# Click "Start Monitoring" on detected PR
```

#### Option B: Command Line

```bash
# Auto-detect and monitor current branch's PR
PR_NUM=$(bash .pr_monitor/pr-monitor.sh detect)
bash .pr_monitor/pr-monitor.sh start $PR_NUM

# Or specify PR number directly
bash .pr_monitor/pr-monitor.sh start 123

# List running monitors
bash .pr_monitor/pr-monitor.sh list

# Stop monitoring
bash .pr_monitor/pr-monitor.sh stop 123
```

## File Structure

```
.pr_monitor/
├── .env                        # Configuration (gitignored)
├── .env.example               # Configuration template
├── .gitignore                 # Ignore patterns
├── README.md                  # This file
├── pr-monitor.sh              # Main entry point
├── data/                      # Local database and state
│   ├── pr_tracking.db        # SQLite database
│   └── state/                # Per-PR state files
├── logs/                      # Log files
│   └── pr_<NUMBER>.log       # Per-PR logs
├── scripts/                   # Shell scripts
│   ├── check_pr_status.sh    # Main monitoring script
│   ├── init_pr_db.sh         # Database initialization
│   ├── query_pr_db.sh        # Database query tool
│   └── utils.sh              # Shared utilities
└── dashboard/                 # Web dashboard
    ├── src/                   # TypeScript source
    ├── public/                # Static assets
    └── dist/                  # Compiled output
```

## How It Works

1. **Detection**: System detects PR for current Git branch using `gh pr list`
2. **Manual Start**: User clicks "Start Monitoring" in dashboard (or runs CLI command)
3. **Polling**: Script polls GitHub API every 60 seconds for PR status
4. **Storage**: Stores events in local SQLite database (`.pr_monitor/data/pr_tracking.db`)
5. **Actions**: Triggers Claude CLI commands when events occur (CI failures, new comments, etc.)

## Configuration

Edit `.pr_monitor/.env` to customize:

- `GITHUB_TOKEN`: GitHub PAT (auto-detected from `gh auth token`)
- `GITHUB_REPO`: Repository name (auto-detected from `git remote`)
- `CLAUDE_CLI`: Path to Claude CLI (default: `claude`)
- `CHECK_INTERVAL`: Polling interval in seconds (default: 60)
- `DEBUG`: Enable debug logging (default: false)
- `PUSHOVER_USER`: Pushover user key (optional, for push notifications)
- `PUSHOVER_TOKEN`: Pushover API token (optional, for push notifications)

See [PIPELINE_NOTIFICATIONS.md](PIPELINE_NOTIFICATIONS.md) for Pushover setup.

## Database Schema

The SQLite database includes tables for:

- `prs`: Pull request metadata
- `comments`: PR comments and reviews
- `workflows`: CI/CD workflow runs
- `activities`: General PR events
- `check_history`: Status check history

Query the database:
```bash
bash .pr_monitor/scripts/query_pr_db.sh list
bash .pr_monitor/scripts/query_pr_db.sh pr 123
```

## Portability

This folder is completely self-contained and can be:

1. **Copied** to any Git repository
2. **Committed** to version control (database/logs are gitignored)
3. **Shared** with team members

Just copy `.pr_monitor/` to a new repo and run:
```bash
cp .pr_monitor/.env.example .pr_monitor/.env
bash .pr_monitor/scripts/init_pr_db.sh
bash .pr_monitor/pr-monitor.sh dashboard
```

## Troubleshooting

### "No PR detected"
- Ensure current branch has an open PR: `gh pr list --head $(git branch --show-current)`
- Check GitHub CLI authentication: `gh auth status`

### "Database locked"
- Only one monitor per PR should run at a time
- Check running monitors: `bash .pr_monitor/pr-monitor.sh list`
- Kill stuck monitors: `pkill -f check_pr_status.sh`

### Dashboard won't start
- Install dependencies: `cd .pr_monitor/dashboard && npm install`
- Build frontend: `npm run build`
- Check Node.js version: `node --version` (requires 18+)

## License

See repository root for license information.
