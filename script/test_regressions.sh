#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/TungBox/Services/ConfigCompatibilityChecker.swift \
  Sources/TungBox/MainWindow/FixedSidebarLayout.swift script/regressions/main.swift \
  -o "$TEST_DIR/regressions"
"$TEST_DIR/regressions"
