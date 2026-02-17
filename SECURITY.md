# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability within PR Monitor, please send an email to the repository maintainers via GitHub. All security vulnerabilities will be promptly addressed.

Please include the following information:

1. **Type of issue** (e.g. buffer overflow, SQL injection, cross-site scripting, etc.)
2. **Full paths of source file(s)** related to the manifestation of the issue
3. **Location** of the affected source code (tag/branch/commit or direct URL)
4. **Step-by-step instructions** to reproduce the issue
5. **Proof-of-concept or exploit code** (if possible)
6. **Impact** of the issue, including how an attacker might exploit it

### What to Expect

- **Acknowledgment**: We'll acknowledge receipt of your vulnerability report within 48 hours
- **Updates**: We'll send you regular updates about our progress
- **Disclosure**: We'll coordinate with you on the disclosure timeline
- **Credit**: We'll give you credit for the discovery (unless you prefer to remain anonymous)

## Security Best Practices

When using PR Monitor:

1. **GitHub Token Security**
   - Never commit your GitHub token to version control
   - Use environment variables or the `.env` file (which is gitignored)
   - Rotate tokens regularly
   - Use tokens with minimal required scopes

2. **Database Security**
   - The SQLite database is stored locally in `.pr_monitor/data/`
   - Ensure this directory has appropriate file permissions
   - Don't share database files that may contain sensitive information

3. **Pushover Notifications**
   - Keep your Pushover tokens in `.env` file only
   - Never commit notification credentials

4. **Claude CLI**
   - Ensure Claude CLI is properly authenticated
   - Review automated commands before execution

5. **Web Dashboard**
   - The dashboard runs on localhost by default
   - Don't expose it to the internet without proper authentication
   - Use in trusted network environments only

## Dependencies

We regularly update dependencies to address security vulnerabilities:

- Run `npm audit` in the dashboard directory to check for vulnerabilities
- Update dependencies with `npm audit fix`
- Check for GitHub security advisories

## Secure Development

Contributors should:

- Never commit secrets or credentials
- Use `shellcheck` for shell script security
- Follow secure coding practices
- Test changes for security implications
- Review third-party dependencies before adding

## Contact

For security concerns, please open a private security advisory on GitHub or contact the maintainers directly.
