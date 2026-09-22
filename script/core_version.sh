#!/bin/sh

verify_core_version() {
  core_binary="$1"
  expected_version="$2"
  version_output="$("$core_binary" version 2>&1)" || {
    echo "Unable to execute bundled sing-box Core: $core_binary" >&2
    return 1
  }
  actual_version="$(printf '%s\n' "$version_output" | sed -nE 's/^sing-box version v?([^[:space:]]+).*$/\1/p' | head -n 1)"
  if [ "$actual_version" != "$expected_version" ]; then
    echo "Bundled sing-box Core version mismatch: expected $expected_version, got ${actual_version:-unknown}" >&2
    return 1
  fi
}
