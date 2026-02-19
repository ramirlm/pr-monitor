#!/usr/bin/env bash
#
# postinstall.sh - NPM postinstall script
#
# This runs after npm install to set up the package

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PR Monitor - GitHub PR Monitoring System"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Installation complete!"
echo ""
echo "📦 To use PR Monitor in a repository:"
echo ""
echo "  1. Navigate to your Git repository:"
echo "     cd /path/to/your/repo"
echo ""
echo "  2. Run pr-monitor (it will auto-initialize):"
echo "     pr-monitor dashboard"
echo ""
echo "  Or initialize manually:"
echo "     pr-monitor init"
echo ""
echo "📚 Documentation:"
echo "  • Quick Start: $(npm root -g)/pr-monitor/QUICK_START.md"
echo "  • Full README: $(npm root -g)/pr-monitor/README.md"
echo ""
echo "🔧 Requirements:"
echo "  • GitHub CLI: gh auth login"
echo "  • Node.js 18+"
echo "  • Claude CLI (optional): for automation features"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
