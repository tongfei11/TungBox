#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library Sources/TungBox/Core/Models.swift Sources/TungBox/MD3Views.swift Sources/TungBox/MainWindow/FixedSidebarLayout.swift script/ui-regressions/main.swift -o "$TEST_DIR/ui"
"$TEST_DIR/ui"
