# PR Monitor Dashboard

A web interface for managing and tracking GitHub PR monitoring jobs.

## Features

- 📊 **Dashboard Overview** - View running monitors and PR statistics
- 🔍 **Running Monitors** - See all active PR monitors with CPU/memory usage
- 🛑 **Stop Monitors** - Stop monitoring jobs directly from the UI
- 📝 **PR Details** - View PR information, comments, workflows, and activities
- ✅ **Comment Tracking** - Mark comments as addressed with notes
- 🔄 **Auto-refresh** - Dashboard updates every 30 seconds

## Tech Stack

- **Backend**: Node.js + Express + TypeScript
- **Frontend**: HTML + TypeScript (Vanilla JS)
- **Database**: SQLite3 (better-sqlite3)

## Installation

```bash
cd web-dashboard
npm install
```

## Usage

### Start the Dashboard

```bash
./start.sh
```

Or manually:

```bash
# Build TypeScript
npm run build

# Build frontend
bash build-frontend.sh

# Start server
npm start
```

The dashboard will be available at: **http://localhost:3000**

### Development Mode

```bash
# Watch TypeScript changes
npm run watch

# In another terminal, run the server
npm run dev
```

## Environment Variables

- `PORT` - Server port (default: 3000)
- `DB_PATH` - Path to SQLite database (default: `~/.pr_monitor/pr_tracking.db`)

## API Endpoints

### Monitors
- `GET /api/monitors` - List running monitors
- `POST /api/monitors/stop/:pid` - Stop a monitor

### PRs
- `GET /api/prs` - List all tracked PRs
- `GET /api/prs/:prNumber` - Get PR details
- `GET /api/prs/:prNumber/comments` - Get PR comments
- `GET /api/prs/:prNumber/workflows` - Get PR workflows
- `GET /api/prs/:prNumber/activities` - Get PR activities

### Comments
- `POST /api/comments/:commentId/address` - Mark comment as addressed

### Stats
- `GET /api/stats` - Get overall statistics

## Screenshots

### Dashboard
Shows running monitors and tracked PRs with real-time statistics.

### PR Detail View
- **Overview**: PR metadata and links
- **Comments**: All comments with addressed status
- **Workflows**: Workflow runs with success/failure details
- **Activities**: Complete activity log

## Features in Detail

### Running Monitors
- View all active PR monitoring processes
- See resource usage (CPU, memory, runtime)
- Stop monitors with one click

### PR Tracking
- Track all monitored PRs across repositories
- View comment counts and unaddressed comments
- See workflow status and failures
- Click any PR to view detailed information

### Comment Management
- View all PR comments (review and issue comments)
- Mark comments as addressed with optional notes
- Filter addressed vs unaddressed comments

### Workflow Monitoring
- See all workflow runs with timestamps
- View failed workflows with error details
- Track workflow success rate

### Activity Log
- Complete timeline of PR events
- Comment posts, workflow runs, monitor actions
- Detailed activity tracking

## Troubleshooting

### Database not found
Run the init script first:
```bash
../shell-scripts/init_pr_db.sh
```

### Port already in use
Change the port:
```bash
PORT=3001 npm start
```

### TypeScript errors
Rebuild:
```bash
npm run build
bash build-frontend.sh
```

## License

MIT
