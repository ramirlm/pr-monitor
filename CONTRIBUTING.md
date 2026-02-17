# Contributing to PR Monitor

Thank you for your interest in contributing to PR Monitor! This document provides guidelines and instructions for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/pr-monitor.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes thoroughly
6. Commit with clear messages
7. Push to your fork
8. Open a Pull Request

## Development Setup

### Prerequisites

- Git
- Node.js 18+
- Bash shell (macOS/Linux)
- GitHub CLI (`gh`) installed and authenticated
- SQLite3 (usually pre-installed)

### Installation

```bash
# Clone the repository
git clone https://github.com/ramirlm/pr-monitor.git
cd pr-monitor

# Install dashboard dependencies
cd dashboard
npm install
npm run build
cd ..

# Initialize the database (for testing)
bash scripts/init_pr_db.sh
```

### Running Locally

```bash
# Start the dashboard
bash pr-monitor.sh dashboard

# Or run scripts directly
bash scripts/check_pr_status.sh 123  # Monitor PR #123
```

## Code Style

### Shell Scripts

- Use `set -euo pipefail` at the top of scripts
- Use shellcheck for linting
- Follow existing code formatting
- Add comments for complex logic
- Use meaningful variable names in UPPER_CASE for globals

### TypeScript/JavaScript

- Follow existing code style
- Use meaningful variable names in camelCase
- Add JSDoc comments for functions
- Keep functions focused and small

### Documentation

- Update README.md for user-facing changes
- Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/)
- Add inline comments for complex logic
- Update relevant documentation files

## Testing

### Manual Testing

Before submitting a PR:

1. Test the installation process
2. Test PR detection: `bash pr-monitor.sh detect`
3. Test monitoring: `bash pr-monitor.sh start <PR_NUM>`
4. Test the dashboard: `bash pr-monitor.sh dashboard`
5. Verify database operations work correctly
6. Check logs for errors

### Test Scripts

Run existing test scripts:

```bash
bash scripts/test_check_pr_status.sh
bash scripts/test_pipeline_notifications.sh
bash scripts/test_integration_notifications.sh
```

## Pull Request Guidelines

### Before Submitting

- [ ] Test your changes locally
- [ ] Update documentation if needed
- [ ] Update CHANGELOG.md
- [ ] Ensure scripts are executable (`chmod +x`)
- [ ] Check for spelling and grammar
- [ ] Verify backwards compatibility

### PR Description

Include in your PR:

1. **What**: Brief description of the change
2. **Why**: Problem being solved or feature being added
3. **How**: Technical approach taken
4. **Testing**: How you tested the changes
5. **Screenshots**: If UI changes are involved

### Commit Messages

Use clear, descriptive commit messages:

```
Add feature: Brief description

Detailed explanation of what changed and why.
May span multiple lines.

Fixes #123
```

## Project Structure

```
pr-monitor/
├── bin/              # NPM binary wrapper
├── scripts/          # Core shell scripts
│   ├── check_pr_status.sh   # Main monitoring loop
│   ├── init_pr_db.sh        # Database initialization
│   ├── utils.sh             # Shared utilities
│   └── ...
├── dashboard/        # Web dashboard
│   ├── src/          # TypeScript backend
│   ├── public/       # Frontend files
│   └── package.json
├── pr-monitor.sh     # Main CLI entry point
└── README.md
```

## Key Components

### Main Entry Point
- `pr-monitor.sh`: Command dispatcher
- `bin/pr-monitor`: NPM wrapper

### Core Scripts
- `check_pr_status.sh`: Background monitoring loop
- `init_pr_db.sh`: Database setup
- `query_pr_db.sh`: Database queries
- `utils.sh`: Shared functions

### Dashboard
- `dashboard/src/server-simple.ts`: Express API server
- `dashboard/public/`: Frontend UI

## Adding Features

### Adding a New Command

1. Add command handler in `pr-monitor.sh`
2. Create script in `scripts/` if needed
3. Update usage/help text
4. Update README.md
5. Add tests

### Adding Dashboard Endpoints

1. Add route in `dashboard/src/server-simple.ts`
2. Update frontend in `dashboard/public/app.js`
3. Rebuild: `cd dashboard && npm run build`
4. Test the endpoint

### Modifying Database Schema

1. Update `scripts/init_pr_db.sh`
2. Test with fresh database
3. Document schema changes
4. Update query functions

## Release Process

1. Update version in `package.json`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.0.0`
4. Push tag: `git push --tags`
5. Publish to NPM: `npm publish`

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions
- Check existing issues and PRs first

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Help others learn and grow
- Focus on what's best for the project

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
