#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library Sources/TungBox/Core/Models.swift Sources/TungBox/MD3Views.swift script/dialog-regressions/main.swift -o "$TEST_DIR/dialog"
"$TEST_DIR/dialog"
