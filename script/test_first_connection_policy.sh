#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

console_body="$(sed -n '/func showConsoleWindow()/,/^    }/p' Sources/TungBox/main.swift)"
if printf '%s\n' "$console_body" | grep -q 'checkAppUpdateInBackground'; then
  echo "FAIL: opening the console still checks GitHub before the first connection" >&2
  exit 1
fi

grep -q 'runDeferredNetworkChecksAfterConnection(proxyPort: port)' Sources/TungBox/main.swift
grep -q 'runDeferredNetworkChecksAfterConnection(proxyPort: nil)' Sources/TungBox/MainWindow/MainWindowController+Settings.swift

test_binary="$(mktemp /tmp/tungbox-first-connection.XXXXXX)"
trap 'rm -f "$test_binary"' EXIT
swiftc \
  Sources/TungBox/Core/RuleSetRuntime.swift \
  Sources/TungBox/Core/StartupNetworkPolicy.swift \
  script/test_core_logic.swift \
  -o "$test_binary"
"$test_binary"

for file in \
  geoip-cn.srs \
  geosite-cn.srs \
  geosite-geolocation-_cn.srs \
  geosite-private.srs
do
  test -s "Sources/TungBox/Resources/RuleSets/$file"
done

echo "PASS: subscriptions can use another system proxy without adding an automatic GitHub dependency"
