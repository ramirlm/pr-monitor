#!/usr/bin/env bash
#
# start.sh
# Install dependencies and start the PR Monitor Dashboard
#

set -euo pipefail

echo "🚀 Starting PR Monitor Dashboard..."
echo ""

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo ""
fi

# Build TypeScript
echo "🔨 Building TypeScript..."
npm run build

# Build frontend
echo "🎨 Building frontend..."
bash build-frontend.sh
echo ""

# Start server
echo "✅ Starting server..."
echo ""
npm start
