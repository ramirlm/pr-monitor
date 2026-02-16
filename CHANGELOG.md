# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-02-16

### Added
- Initial release of PR Monitor
- Auto-detection of PRs from current Git branch
- Manual trigger for PR monitoring from web dashboard
- Real-time tracking of CI checks, reviews, and comments
- Push notifications via Pushover for pipeline completion
- Claude CLI integration for automated assistance
- Local SQLite database for repository-specific tracking
- Portable design - drop into any Git repository
- Web dashboard for visual monitoring and management
- Command-line interface for PR management
- Workflow tracking and error extraction
- Automated fixing suggestions via Claude
- Real-time log streaming
- Duplicate prevention mechanisms
- Comprehensive documentation

### Features
- **Monitoring**: Background polling of GitHub API for PR status
- **Dashboard**: Express + TypeScript web UI at http://localhost:3000
- **CLI**: Command-line interface with `pr-monitor` command
- **Notifications**: Pushover integration for mobile/desktop alerts
- **Automation**: Claude CLI integration for automated PR assistance
- **Database**: SQLite for local state and history tracking
- **Portability**: Self-contained folder structure

### Documentation
- Main README with quick start guide
- Quick Start guide for first-time users
- Pipeline notifications setup guide
- Workflow tracking documentation
- Error extraction guide
- Automated fixing documentation
- Real-time logs guide
- Duplicate prevention guide
- Notification examples

### Requirements
- Git repository with GitHub remote
- GitHub CLI (gh) installed and authenticated
- Node.js 18+
- Claude CLI (optional, for automation features)
- Pushover account (optional, for notifications)

## [Unreleased]

### Planned
- NPM package improvements
- Additional CI/CD platform support
- Enhanced notification options
- API for external integrations
