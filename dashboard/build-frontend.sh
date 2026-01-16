#!/usr/bin/env bash
# Build frontend TypeScript to JavaScript

set -euo pipefail

echo "Building frontend TypeScript..."

# Compile app.ts to JavaScript for browser
npx tsc --target ES2020 --module ES2020 --lib ES2020,DOM --outDir public --skipLibCheck src/app.ts

echo "✅ Frontend built successfully!"
echo "Output: public/app.js"
