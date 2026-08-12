#!/usr/bin/env bash
# setup.sh — one-shot iOS project materialisation. Run after cloning so the
# generated CyberpunkMonsterCrawl.xcodeproj is created and opened in Xcode.
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen via Homebrew (one-time)…"
  brew install xcodegen
fi

xcodegen generate
open -a Xcode *.xcodeproj 2>/dev/null || \
  echo "✓ Project generated. Open the .xcodeproj in Xcode to start."
