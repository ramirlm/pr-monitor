# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

PR Monitor is a self-contained, portable system for monitoring GitHub Pull Requests with automated tracking and Claude CLI integration. It runs locally, stores data in SQLite, and provides both a web dashboard and CLI interface for managing PR monitoring jobs.

**Key characteristics:**
- Portable (can be dropped into any Git repository)
- Self-contained (all scripts, database, and logs in `.pr_monitor/`)
- Auto-detection of GitHub repo and authentication via gh CLI
- Background polling of PR status (comments, CI checks, workflows)
- Web dashboard for visual monitoring and management

---

## Common Development Commands

### Setup & Initialization

```bash
# Copy environment configuration (optional - auto-detection works)
cp .env.example .env

# Initialize SQLite database
./pr-monitor.sh init
# OR directly:
bash scripts/init_pr_db.sh
```

### Starting the Dashboard

```bash
# Start web dashboard at http://localhost:3000
./pr-monitor.sh dashboard

# Dashboard development
cd dashboard
npm install
npm run build          # Build TypeScript backend
bash build-frontend.sh # Build frontend
npm run dev            # Development mode
npm run watch          # Watch TypeScript changes
```

### PR Monitoring

```bash
# Auto-detect and show current branch's PR
./pr-monitor.sh detect

# Start monitoring a PR (runs in background)
./pr-monitor.sh start 123
./pr-monitor.sh start 123 owner/repo  # With specific repo

# List running monitors
./pr-monitor.sh list

# Stop monitoring a PR
./pr-monitor.sh stop 123
```

### Database Queries

```bash
# Query database directly
./pr-monitor.sh query list              # List all PRs
./pr-monitor.sh query pr 123            # Get PR details
./pr-monitor.sh query comments 123      # Get PR comments

# OR use script directly:
bash scripts/query_pr_db.sh list
bash scripts/query_pr_db.sh pr 123
```

### Logs

```bash
# View logs for specific PR
tail -f logs/pr_123.log

# View real-time monitor output
ps aux | grep "check_pr_status.sh"
```

---

## Project Architecture

### Directory Structure

```
.pr_monitor/
├── pr-monitor.sh              # Main CLI entry point
├── .env                       # Configuration (gitignored)
├── .env.example              # Configuration template
├── data/                     # Runtime data
│   ├── pr_tracking.db        # SQLite database
│   └── state/                # Per-PR JSON state files
├── logs/                     # Log files (pr_<NUMBER>.log)
├── scripts/                  # Shell scripts
│   ├── check_pr_status.sh    # Main monitoring loop (runs in background)
│   ├── init_pr_db.sh         # Database initialization
│   ├── query_pr_db.sh        # Database query utility
│   └── utils.sh              # Shared utilities (load_env, detect_current_pr)
└── dashboard/                # Web dashboard
    ├── src/                  # TypeScript backend
    │   ├── server-simple.ts  # Express API server
    │   └── app.ts            # Alternative server implementation
    ├── public/               # Frontend files
    │   ├── index.html        # Main UI
    │   ├── app.js            # Frontend JavaScript
    │   └── styles.css        # Styles
    ├── dist/                 # Compiled TypeScript
    └── package.json          # Dependencies
```

### Component Responsibilities

**Main Scripts:**
- `pr-monitor.sh`: Command dispatcher and entry point
- `scripts/check_pr_status.sh`: Background monitoring loop that polls GitHub API every N seconds
- `scripts/utils.sh`: Shared functions for env loading, PR detection, repo root discovery

**Dashboard:**
- `server-simple.ts`: Express server with REST API for monitors, PRs, comments, workflows
- `public/app.js`: Frontend client that polls `/api/*` endpoints and updates UI
- Uses `sqlite3` CLI directly for database queries (no ORM)

### Data Flow

1. **PR Detection**: `utils.sh:detect_current_pr()` uses `gh pr list --head $(git branch --show-current)`
2. **Monitor Start**: `pr-monitor.sh start` launches `check_pr_status.sh` as background process
3. **Polling Loop**: `check_pr_status.sh` polls GitHub API every `CHECK_INTERVAL` seconds
4. **Storage**: Events stored in SQLite via direct `sqlite3` CLI calls
5. **Dashboard**: Express server queries SQLite and serves JSON to frontend
6. **Frontend**: Vanilla JS polls API every 30 seconds and updates DOM

### Database Schema

Tables (defined in `scripts/init_pr_db.sh`):

- **prs**: PR metadata (pr_number, repo, title, state, author, url)
- **comments**: PR comments (comment_id, comment_type, author, body, addressed status)
- **workflows**: CI workflow runs (run_id, workflow_name, status, conclusion, failure_details)
- **check_history**: Monitoring iteration logs (check_time, pr_state, counts)
- **activities**: Activity log (activity_type, summary, details)

All tables use SQLite with timestamps and foreign keys.

---

## Key Development Patterns

### Environment Configuration

Auto-detection with fallback to `.env`:

```bash
# In scripts/utils.sh
load_env() {
    # 1. Load .env if exists
    # 2. Auto-detect GITHUB_REPO from git remote
    # 3. Auto-detect GITHUB_TOKEN from gh auth token
    # 4. Set defaults for CHECK_INTERVAL, CLAUDE_CLI
}
```

Always use `load_env` at the start of scripts.

### Repository Root Detection

```bash
# Always use get_repo_root() from utils.sh
REPO_ROOT=$(get_repo_root)

# This function tries:
# 1. git rev-parse --show-toplevel
# 2. Falls back to relative path calculation
```

All paths should be relative to `REPO_ROOT/.pr_monitor/`.

### PR Detection

```bash
# From scripts/utils.sh
detect_current_pr() {
    local branch=$(git branch --show-current 2>/dev/null)
    local pr_data=$(gh pr list --head "${branch}" --json number 2>/dev/null)
    echo "${pr_data}" | jq -r '.[0].number // empty'
}
```

### Database Operations

Use `sqlite3` CLI with `-json` flag for JSON output:

```bash
# Query example
sqlite3 -json "${DB_PATH}" "SELECT * FROM prs WHERE pr_number = ${PR_NUM}"

# Insert example
sqlite3 "${DB_PATH}" <<EOF
INSERT OR REPLACE INTO prs (pr_number, repo, title, state, author, url)
VALUES (${PR_NUM}, '${REPO}', '${TITLE}', '${STATE}', '${AUTHOR}', '${URL}');
EOF
```

### API Endpoint Pattern (Dashboard)

```typescript
// In dashboard/src/server-simple.ts
app.get('/api/endpoint', async (req, res) => {
  const result = await querySqlite("SELECT ...");
  res.json({ success: true, data: JSON.parse(result) });
});
```

All API responses follow format: `{ success: boolean, ...data }`

### Background Process Management

```bash
# Start monitor in background
bash scripts/check_pr_status.sh 123 &
local pid=$!

# Find running monitors
ps aux | grep "check_pr_status.sh" | grep -v grep

# Stop monitor
pkill -f "check_pr_status.sh 123"
```

---

## Common Development Scenarios

### Adding a New API Endpoint

1. **Add route** in `dashboard/src/server-simple.ts`
2. **Define SQL query** (follow existing patterns with `-json` flag)
3. **Update frontend** in `dashboard/public/app.js` to call new endpoint
4. **Rebuild**: `cd dashboard && npm run build`

### Modifying Database Schema

1. **Update SQL** in `scripts/init_pr_db.sh`
2. **Drop and recreate** for development: `rm data/pr_tracking.db && ./pr-monitor.sh init`
3. **Test queries** with `scripts/query_pr_db.sh`

### Adding New Monitoring Logic

1. **Edit** `scripts/check_pr_status.sh` (main monitoring loop)
2. **Use GitHub CLI**: Prefer `gh pr view`, `gh api` for GitHub data
3. **Log events** to both `LOG_FILE` and database
4. **Test** by running monitor directly: `bash scripts/check_pr_status.sh 123`

### Testing Dashboard Changes

```bash
cd dashboard

# Development workflow
npm run watch           # Terminal 1: Watch TypeScript
bash build-frontend.sh  # Terminal 2: Rebuild frontend when needed
npm run dev             # Terminal 3: Run server

# Or build and run
npm run build
bash build-frontend.sh
npm start
```

### Debugging Monitor Issues

```bash
# Enable debug mode
DEBUG=true ./pr-monitor.sh start 123

# Watch logs in real-time
tail -f logs/pr_123.log

# Check state file
cat data/state/pr_123.json | jq

# Query database
./pr-monitor.sh query pr 123
```

---

## Configuration

### Environment Variables

Set in `.env` (optional, auto-detected):

- `GITHUB_TOKEN`: GitHub PAT (auto-detected from `gh auth token`)
- `GITHUB_REPO`: Format "owner/repo" (auto-detected from git remote)
- `CLAUDE_CLI`: Path to Claude CLI (default: `claude`)
- `CHECK_INTERVAL`: Polling interval in seconds (default: 60)
- `DEBUG`: Enable debug logging (default: false)

### Dashboard Environment

- `PORT`: Server port (default: 3000)
- `DB_PATH`: Path to SQLite database (auto-detected: `${REPO_ROOT}/.pr_monitor/data/pr_tracking.db`)

---

## Tech Stack

- **Shell**: Bash scripts with `set -euo pipefail`
- **GitHub Integration**: GitHub CLI (`gh`) and GitHub API
- **Database**: SQLite3 with direct CLI queries
- **Backend**: Node.js + Express + TypeScript
- **Frontend**: Vanilla JavaScript (no framework)
- **Process Management**: Background processes with `ps`/`pkill`

---

## Critical Rules

### Git Restrictions

**IMPORTANT: AI assistants have READ-ONLY access to Git operations.**

**ALLOWED Git Operations:**
- `git status` - Check repository status
- `git log` - View commit history
- `git show` - View commit details
- `git diff` - View changes
- `git branch --show-current` - Get current branch
- `git remote` - View remotes
- `gh pr view` - View PR details
- `gh pr list` - List PRs
- `gh api` - Read GitHub API data

**DISALLOWED Git Operations:**
- ❌ `git commit` - No commits
- ❌ `git push` - No pushing
- ❌ `git pull` - No pulling
- ❌ `git merge` - No merging
- ❌ `git rebase` - No rebasing
- ❌ `git reset` - No resetting
- ❌ `git checkout` - No branch switching
- ❌ `git branch` (write operations) - No branch creation/deletion
- ❌ `gh pr create` - No PR creation
- ❌ `gh pr merge` - No PR merging
- ❌ `gh pr close` - No PR closing
- ❌ Any other write operations to Git or GitHub

AI assistants may analyze code, suggest changes, and provide recommendations, but must not execute any Git write operations.

### Portability Requirements

- All paths must be relative to `REPO_ROOT/.pr_monitor/`
- Database and state files must stay in `data/`
- No hardcoded paths outside `.pr_monitor/`
- Use `get_repo_root()` from `utils.sh` for all path resolution

### Database Access

- Always use `sqlite3 -json` for queries returning data
- Use `INSERT OR REPLACE` for upserts
- Use transactions for multi-statement writes
- Never edit database with multiple concurrent processes

### Background Processes

- Only one monitor per PR should run at a time
- Always check if monitor is running before starting new one
- Store PID and PR number for process management
- Use `pkill -f` with specific PR number to avoid killing wrong process

### GitHub API Usage

- Prefer `gh` CLI over raw API calls
- Always check `gh auth status` before operations
- Handle rate limiting (5000 requests/hour for authenticated)
- Use `--json` flag for structured output

---

## Testing

### Manual Testing

```bash
# 1. Initialize
./pr-monitor.sh init

# 2. Start dashboard
./pr-monitor.sh dashboard

# 3. In browser, visit http://localhost:3000
# 4. Click "Start Monitoring" on detected PR
# 5. Verify logs: tail -f logs/pr_<NUM>.log
# 6. Verify database: ./pr-monitor.sh query pr <NUM>
# 7. Stop monitor: ./pr-monitor.sh stop <NUM>
```

### Integration Testing

```bash
# Test PR detection
./pr-monitor.sh detect

# Test monitor lifecycle
PR_NUM=$(./pr-monitor.sh detect | grep -oE '[0-9]+' | head -1)
./pr-monitor.sh start ${PR_NUM}
./pr-monitor.sh list
sleep 10
./pr-monitor.sh stop ${PR_NUM}

# Test database queries
./pr-monitor.sh query list
```

---

## Resources

- **Main README**: `README.md` - Setup and usage instructions
- **Dashboard README**: `dashboard/README.md` - Dashboard-specific docs
- **GitHub CLI Docs**: https://cli.github.com/manual/
- **SQLite Docs**: https://www.sqlite.org/cli.html
