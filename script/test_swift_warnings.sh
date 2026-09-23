#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

cd "$ROOT_DIR"

# Force the files that previously emitted concurrency diagnostics to rebuild,
# even when SwiftPM's incremental cache is warm.
touch \
  Sources/TungBox/MainWindow/MainWindowController+Connections.swift \
  Sources/TungBox/MainWindow/MainWindowController+Home.swift \
  Sources/TungBox/main.swift

if ! swift build >"$LOG_FILE" 2>&1; then
  cat "$LOG_FILE"
  exit 1
fi

if grep -q "warning:" "$LOG_FILE"; then
  cat "$LOG_FILE"
  echo "Swift build emitted warnings." >&2
  exit 1
fi

echo "Swift build completed without warnings."
