#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/TungBox/Core/Models.swift Sources/TungBox/Core/Utilities.swift \
  Sources/TungBox/Core/RuleSetFormat.swift Sources/TungBox/Core/Store.swift \
  Sources/TungBox/Core/RuleRouting.swift script/ruleset-regressions/main.swift -o "$TEST_DIR/rulesets"
TUNGBOX_RULE_FIXTURES="$TEST_DIR" "$TEST_DIR/rulesets"
if [[ -n "${TUNGBOX_CORE_PATH:-}" ]]; then
  python3 script/ruleset-regressions/runtime_probe.py "$TEST_DIR" "$TUNGBOX_CORE_PATH"
fi
