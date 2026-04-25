#!/bin/bash

# Build script for Seashell

set -e

echo "Building Seashell..."
echo "================================"

# Clean previous builds
echo "Cleaning previous builds..."
swift package clean

# Build in release mode
echo "Building in release mode..."
swift build -c release

# Create a convenient symlink
echo "Creating symlink..."
ln -sf .build/release/seashell seashell

echo ""
echo "Build complete!"
echo ""
echo "Executable location:"
echo "  $(pwd)/.build/release/seashell"
echo ""
echo "To register Seashell with Claude Desktop:"
echo "1. Edit ~/Library/Application\\ Support/Claude/claude_desktop_config.json"
echo "2. Add an mcpServers entry pointing to: $(pwd)/.build/release/seashell"
echo "3. Restart Claude Desktop"
echo ""
echo "See config/claude-desktop-config.json for a template."
echo ""
echo "To test locally:"
echo "  ./seashell --verbose"
