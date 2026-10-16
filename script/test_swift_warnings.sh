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
  Sources/TungBox/MainWindow/MainWindowController+Nodes.swift \
  Sources/TungBox/MainWindow/MainWindowController+Configuration.swift \
  Sources/TungBox/MainWindow/MainWindowController+Runtime.swift \
  Sources/TungBox/MainWindow/MainWindowController+Settings.swift \
  Sources/TungBox/MainWindow/MainWindowController+CoreSettings.swift \
  Sources/TungBox/MainWindow/MainWindowController+TUNService.swift \
  Sources/TungBox/MainWindow/MainWindowController+Appearance.swift \
  Sources/TungBox/MainWindow/MainWindowController+Rules.swift \
  Sources/TungBox/MainWindow/MainWindowController+RuleEditor.swift \
  Sources/TungBox/MainWindow/MainWindowController+RuleSets.swift \
  Sources/TungBox/Core/RuleConfigProjector.swift \
  Sources/TungBox/MainWindow/FixedSidebarLayout.swift \
  Sources/TungBox/MainWindow/ConsoleWindowDelegate.swift \
  Sources/TungBox/MainWindow/RuleTableLayout.swift \
  Sources/TungBox/MainWindow/RuleTableCell.swift \
  Sources/TungBox/Views/HomeDashboardLayout.swift \
  Sources/TungBox/Views/MD3Theme.swift \
  Sources/TungBox/Views/MD3Buttons.swift \
  Sources/TungBox/Views/MD3Inputs.swift \
  Sources/TungBox/Views/MD3Indicators.swift \
  Sources/TungBox/Views/MD3TableViews.swift \
  Sources/TungBox/Views/MD3BusinessViews.swift \
  Sources/TungBox/Views/MD3Dialog.swift \
  Sources/TungBox/MainWindow/MainWindowController.swift \
  Sources/TungBox/AppDelegate.swift \
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
