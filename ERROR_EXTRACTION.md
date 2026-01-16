# Error Extraction and Detailed Failure Analysis

The PR Monitor now extracts detailed error information from failed GitHub Actions workflows, providing actionable data that can be fed directly to AI agents for automated fixes.

## Features

### What Gets Extracted

For every failed job, the monitor extracts:

1. **Failed Step Details**:
   - Step name and number
   - Start and completion timestamps
   - Duration of execution
   - Exact conclusion (failure/cancelled/etc)

2. **Error Context**:
   - Primary error message
   - List of all failed steps (JSON array)
   - Job execution environment (runner name)
   - Direct URLs to GitHub logs

3. **Workflow Context**:
   - Which workflow the job belongs to
   - Workflow run number and ID
   - Commit SHA that triggered the workflow
   - Links to both job and workflow on GitHub

### Structured JSON Output

All error data is available in structured JSON format, making it easy to:
- Parse programmatically
- Feed into AI agents (Claude, GPT, etc.)
- Build custom integrations
- Generate automated fix suggestions

## Usage

### Command Line

#### Show errors for specific PR:
```bash
./pr-monitor.sh errors 4492
```

#### Auto-detect PR from current branch:
```bash
./pr-monitor.sh errors
```

#### Directly call the script:
```bash
bash scripts/show_pr_errors.sh 4492
```

### API Endpoint

#### Get errors as JSON:
```bash
curl http://localhost:3000/api/prs/4492/errors | jq
```

**Response structure:**
```json
{
  "success": true,
  "pr_number": 4492,
  "total_failures": 2,
  "failed_jobs": [
    {
      "workflow": "CI",
      "job": "test-unit",
      "error": "Run tests",
      "failed_steps": [
        {
          "name": "Run tests",
          "number": 5,
          "started_at": "2024-01-15T10:30:00Z",
          "completed_at": "2024-01-15T10:32:15Z",
          "conclusion": "failure"
        },
        {
          "name": "Upload coverage",
          "number": 6,
          "started_at": "2024-01-15T10:32:15Z",
          "completed_at": "2024-01-15T10:32:20Z",
          "conclusion": "failure"
        }
      ],
      "job_url": "https://github.com/org/repo/actions/runs/123/jobs/456",
      "workflow_url": "https://github.com/org/repo/actions/runs/123",
      "runner": "GitHub Actions 2",
      "run_id": 123456,
      "run_number": 42,
      "completed_at": "2024-01-15T10:32:20Z"
    }
  ],
  "errors_by_workflow": {
    "CI": [
      {
        "workflow": "CI",
        "job": "test-unit",
        "error": "Run tests",
        ...
      }
    ]
  }
}
```

## Output Format

### Terminal Output

The `./pr-monitor.sh errors` command provides a human-readable report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 FAILED ACTIONS FOR PR #4492
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Found 2 failed job(s)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Workflow: CI
   Job: test-unit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔗 Job URL: https://github.com/org/repo/actions/runs/123/jobs/456
🏃 Runner: GitHub Actions 2
⏱️  Completed: 2024-01-15 10:32:20

📋 Failed Steps:
   • Step 5: Run tests
   • Step 6: Upload coverage

🔍 Fetching detailed error information from GitHub...

📝 Detailed Step Information:

  Step: Run tests
  Number: 5
  Started: 2024-01-15T10:30:00Z
  Completed: 2024-01-15T10:32:15Z
  Duration: 135s

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total Failed Jobs: 2

Failures by Workflow:
workflow_name  failed_jobs  jobs
-------------  -----------  ---------
CI             2            test-unit, build

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 ACTIONABLE JSON OUTPUT (for AI agent)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{
  "pr_number": 4492,
  "total_failures": 2,
  "failed_jobs": [...]
}
```

### JSON Output (for AI Agents)

At the end of the terminal output, you'll find a complete JSON dump that can be:
- Copied and pasted into AI prompts
- Piped to other tools with `| jq`
- Sent to Claude API for automated fix generation
- Used in CI/CD pipelines

## Integration with AI Agents

### Example: Feed to Claude for Automated Fixes

```bash
# Get errors as JSON
ERRORS=$(./pr-monitor.sh errors 4492 | tail -n +$(grep -n "ACTIONABLE JSON" | cut -d: -f1) | jq -c)

# Send to Claude (requires Claude CLI)
echo "Here are the failed GitHub Actions for PR #4492. Please analyze and suggest fixes:

${ERRORS}

Context: This is a Next.js application with TypeScript and Playwright E2E tests." | claude

# Or via API endpoint
curl -s http://localhost:3000/api/prs/4492/errors | \
  jq '.failed_jobs' | \
  claude -p "Analyze these failed CI jobs and suggest fixes"
```

### Example: Generate Fix PRs Automatically

```bash
#!/bin/bash
# auto-fix-ci.sh - Automatically generate fixes for failed CI

PR_NUM=$1
ERRORS=$(curl -s http://localhost:3000/api/prs/${PR_NUM}/errors)

# Check if there are failures
FAILURES=$(echo "${ERRORS}" | jq '.total_failures')

if [[ "${FAILURES}" -eq 0 ]]; then
    echo "No failures to fix!"
    exit 0
fi

# Extract error details
ERROR_SUMMARY=$(echo "${ERRORS}" | jq -r '.failed_jobs[] |
    "Workflow: \(.workflow)\nJob: \(.job)\nError: \(.error)\nSteps: \(.failed_steps | map(.name) | join(", "))\nURL: \(.job_url)\n"')

# Send to Claude for analysis
echo "Analyze these CI failures and generate a fix:

${ERROR_SUMMARY}

Please provide:
1. Root cause analysis
2. Specific code changes needed
3. Files to modify" | claude
```

## How It Works

### During Monitoring

1. **Monitor fetches workflows** every CHECK_INTERVAL seconds
2. **For each workflow**, fetches all jobs via GitHub API
3. **For failed jobs**, extracts step-level details:
   ```bash
   curl -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/org/repo/actions/runs/${RUN_ID}/jobs"
   ```
4. **Parses JSON response** with jq to extract:
   - Failed step names, numbers, timestamps
   - Conclusion status for each step
   - Runner information
5. **Stores in database** as structured JSON in `failed_steps` column

### On Error Query

1. **Reads from database** - All error data stored during monitoring
2. **Enriches with live data** - Optionally fetches fresh details from GitHub API
3. **Formats output** - Both human-readable and machine-parseable JSON
4. **Groups by workflow** - Makes it easy to see patterns

## Database Schema

The `workflow_jobs` table stores detailed error information:

```sql
CREATE TABLE workflow_jobs (
    id INTEGER PRIMARY KEY,
    workflow_id INTEGER NOT NULL,
    pr_id INTEGER NOT NULL,
    job_id INTEGER NOT NULL,           -- GitHub job ID
    job_name TEXT NOT NULL,
    status TEXT NOT NULL,
    conclusion TEXT,
    html_url TEXT,                     -- Direct link to job logs
    runner_name TEXT,
    failed_steps TEXT,                 -- JSON: [{name, number, started_at, completed_at, conclusion}]
    error_message TEXT,                -- First failed step name
    completed_at TIMESTAMP,
    FOREIGN KEY (workflow_id) REFERENCES workflows(id)
);
```

## Advanced Usage

### Query Specific Error Patterns

```bash
# Find all jobs that failed on "Run tests" step
./pr-monitor.sh errors 4492 | jq '.failed_jobs[] | select(.error == "Run tests")'

# Get only TypeScript test failures
./pr-monitor.sh errors 4492 | jq '.failed_jobs[] | select(.job | contains("test")) | select(.workflow | contains("TypeScript"))'

# Extract all unique error messages
./pr-monitor.sh errors 4492 | jq -r '.failed_jobs[].error' | sort -u
```

### Filter by Workflow

```bash
# Get errors only from CI workflow
curl -s http://localhost:3000/api/prs/4492/errors | \
  jq '.errors_by_workflow.CI'

# Count failures per workflow
curl -s http://localhost:3000/api/prs/4492/errors | \
  jq '.errors_by_workflow | to_entries | map({workflow: .key, count: (.value | length)})'
```

### Export for External Analysis

```bash
# Export to CSV
./pr-monitor.sh errors 4492 | \
  jq -r '.failed_jobs[] | [.workflow, .job, .error, .job_url] | @csv' > failures.csv

# Export to Markdown table
./pr-monitor.sh errors 4492 | \
  jq -r '.failed_jobs[] | "| \(.workflow) | \(.job) | \(.error) | [\(.job_url)](\(.job_url)) |"'
```

## Troubleshooting

### "No failed jobs found"

This means all workflows passed! 🎉 The monitor is working correctly.

### Empty `failed_steps` field

- The monitor hasn't run since the failure occurred
- Restart monitor to fetch fresh data: `./pr-monitor.sh stop 4492 && ./pr-monitor.sh start 4492`

### Missing detailed error information

- Check GITHUB_TOKEN is set: `echo $GITHUB_TOKEN`
- Verify API access: `gh auth status`
- Check API rate limits: `gh api rate_limit`

## Best Practices

1. **Monitor continuously** - Let the monitor run to catch failures as they happen
2. **Query programmatically** - Use the API endpoint for integrations
3. **Feed to AI** - Use the JSON output with Claude or other AI agents
4. **Track patterns** - Look at `errors_by_workflow` to identify chronic issues
5. **Link to fixes** - When you fix an error, reference the job URL in your commit message

## Next Steps

With detailed error extraction in place, you can:

1. **Build automated fix workflows** - Use Claude to analyze and suggest fixes
2. **Create dashboards** - Visualize common failure patterns
3. **Set up alerts** - Get notified when specific error patterns occur
4. **Generate reports** - Track CI health over time
5. **Train models** - Use historical error data to improve predictions
