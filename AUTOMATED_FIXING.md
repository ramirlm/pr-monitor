# Automated PR Fixing System

The PR Monitor includes an intelligent automated fixing system that launches specialized Claude agents to fix failures detected in PRs.

## How It Works

### 1. Failure Detection

When the monitor detects a workflow failure, it automatically:
1. Analyzes the failure type
2. Classifies which specialized agent should handle it
3. Prepares detailed context about the failure
4. Launches the appropriate fixing agent

### 2. Specialized Agents

The system includes multiple specialized agents:

| Agent Type | Triggers On | What It Does |
|------------|-------------|--------------|
| **E2E Fix Agent** | E2E test failures | Reads E2E documentation, fixes tests, ensures all checks pass |
| **Lint Fix Agent** | Linting failures | Fixes code style issues following project conventions |
| **Type Fix Agent** | TypeScript errors | Resolves type errors without introducing `any` types |
| **Build Fix Agent** | Build failures | Fixes build issues (imports, dependencies, etc.) |
| **Integration Fix Agent** | Integration test failures | Fixes integration test issues |
| **Unit Test Fix Agent** | Unit test failures | Fixes unit test failures |
| **API Fix Agent** | API compatibility failures | Ensures API compliance with specs |
| **General Fix Agent** | Other failures | General investigation and fixing |

### 3. Agent Workflow

Each agent follows this process:

1. **Read Documentation** - Searches for and reads relevant project documentation (CLAUDE.md, E2E-TESTING.md, etc.)
2. **Analyze Failure** - Reviews the error messages, failed jobs, and PR changes
3. **Fix Issues** - Applies fixes following project conventions and best practices
4. **Run All Checks** - Verifies lint, typecheck, build, tests all pass
5. **Create Commit** - Creates a commit with a clear message
6. **NO PUSH** - Waits for manual review and push

### 4. Real-Time Visibility

All agent actions are streamed to the PR's log file in real-time:
- Watch the dashboard log viewer to see exactly what the agent is doing
- Logs include:
  - Files being read
  - Commands being run
  - Analysis and reasoning
  - Test results
  - Commit creation

### 5. Manual Approval Required

**The agent will NEVER push commits automatically.**

After the agent creates a commit:
1. You receive a Pushover notification
2. Review the commit: `git show HEAD`
3. If approved, push manually: `git push origin <branch>`
4. If not approved, amend or reset the commit

## Notifications

You'll receive Pushover notifications at key points:

1. **Workflow Failed** (Priority: High)
   - Details about the failure
   - AI analysis of the cause

2. **Agent Launching** (Priority: Normal)
   - Which agent type is being launched
   - What it will do

3. **Agent Completed** (Priority: Normal - future enhancement)
   - Summary of changes
   - Commit SHA
   - Reminder to review and push

## Configuration

### Enable/Disable Automated Fixing

To disable automated fixing, set in `.env`:
```bash
AUTO_FIX_ENABLED=false
```

To enable (default):
```bash
AUTO_FIX_ENABLED=true
```

### Configure Claude CLI

The system uses the Claude CLI. Configure the path in `.env`:
```bash
CLAUDE_CLI=claude  # Or full path: /usr/local/bin/claude
```

### Agent Behavior

Agents are configured in `scripts/launch_fixing_agent.sh`. Each agent type has specific instructions tailored to its domain.

## Monitoring Agent Activity

### Via Dashboard

1. Open http://localhost:3000
2. Navigate to "Running Monitors" tab
3. Select the PR from the log viewer dropdown
4. Watch real-time agent output with:
   - `[AGENT]` prefix for agent actions
   - Color-coded log levels
   - Command outputs
   - Test results

### Via CLI

Watch logs directly:
```bash
tail -f .pr_monitor/logs/pr_<NUMBER>.log
```

## Example Flow

### Scenario: E2E Tests Fail

1. **Detection** (Iteration 5)
   ```
   [ERROR] Workflow 'E2E Ghee Sheets' failed!
   [INFO] 🤖 AUTOMATED FIXING AGENT SYSTEM ACTIVATED
   [INFO] 🔍 Classified failure type: e2e-fix
   [INFO] 🚀 Launching e2e-fix agent in background...
   ```

2. **Agent Working** (Takes several minutes)
   ```
   [AGENT] 📄 Reading E2E testing documentation...
   [AGENT] Found: .claude/memories/e2e-testing.md
   [AGENT] Key practices: Use page objects, proper waits, data-testid...
   [AGENT] 🔍 Analyzing failed test: "should display formula bar"
   [AGENT] Root cause: Missing wait for element to be visible
   [AGENT] 📝 Applying fix...
   [AGENT] ✅ Running pnpm lint... PASSED
   [AGENT] ✅ Running pnpm typecheck... PASSED
   [AGENT] ✅ Running pnpm build... PASSED
   [AGENT] ✅ Running pnpm e2e... PASSED
   [AGENT] 📝 Creating commit...
   ```

3. **Agent Complete**
   ```
   [INFO] ✅ Agent completed successfully!
   [INFO] 📝 Commit created: a1b2c3d
   [INFO] 💬 Message: fix(e2e): add proper wait for formula bar visibility
   [INFO] ⚠️  IMPORTANT: Commit created but NOT pushed
   [INFO] ⚠️  Please review the changes and push manually if approved
   ```

4. **Manual Review**
   ```bash
   git show HEAD
   # Review changes...
   git push origin feature/your-branch
   ```

5. **Next Check** (Iteration 6)
   ```
   [INFO] Workflow 'E2E Ghee Sheets' (21234567890): completed - success
   [INFO]   Jobs: 7 total, 0 failed
   [INFO] ✅ Workflow 'E2E Ghee Sheets' passed (7 jobs)
   ```

## Troubleshooting

### Agent Not Launching

Check:
1. Claude CLI is installed: `which claude`
2. CLAUDE_CLI path is correct in `.env`
3. Monitor has sufficient permissions
4. Check monitor logs for errors

### Agent Failed

Common causes:
1. Claude CLI not authenticated
2. Insufficient context/information for fixing
3. Complex issue requiring human intervention
4. Permission issues accessing files

Check agent output in logs for specific error.

### Commit Not Created

Possible reasons:
1. Agent couldn't fix the issue
2. Checks didn't pass after attempted fix
3. Agent encountered an error

Review agent output logs for details.

## Best Practices

### For Users

1. **Monitor the Dashboard** - Watch agent activity in real-time
2. **Review Commits Carefully** - Always review before pushing
3. **Provide Context** - Clear PR descriptions help agents understand intent
4. **Update Documentation** - Keep CLAUDE.md and other docs current

### For Agent Prompts

1. **Be Specific** - Detailed instructions in agent prompts
2. **Reference Docs** - Point agents to relevant documentation
3. **Verify Everything** - Always run all checks before committing
4. **Clear Commit Messages** - Use conventional commit format

## Future Enhancements

Potential improvements:
- [ ] Multiple fix attempts if first fails
- [ ] Learning from successful fixes
- [ ] Custom agent types per project
- [ ] Slack/Discord integration
- [ ] Agent performance metrics
- [ ] Auto-push after user approval via Pushover
- [ ] Rollback mechanism if push fails CI

## Security Considerations

- Agents run with your user permissions
- Agents can modify any file in the repository
- Review all changes before pushing
- Consider running monitors in isolated environments for untrusted PRs

## Summary

The Automated PR Fixing System provides:

✅ Intelligent failure classification
✅ Specialized agents for each failure type
✅ Real-time visibility into agent actions
✅ Automatic commit creation
✅ Manual push approval for safety
✅ Comprehensive logging
✅ Pushover notifications

This system dramatically reduces the time to fix PR issues while maintaining human oversight and control.
