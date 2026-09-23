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

policy_uses="$(grep -c 'StartupNetworkPolicy.directConnectionProxyDictionary' Sources/TungBox/Networking/SubscriptionImporter.swift)"
if [ "$policy_uses" -lt 2 ]; then
  echo "FAIL: subscription downloads are not consistently forced onto the direct physical network" >&2
  exit 1
fi

for file in \
  geoip-cn.srs \
  geosite-cn.srs \
  geosite-geolocation-_cn.srs \
  geosite-private.srs
do
  test -s "Sources/TungBox/Resources/RuleSets/$file"
done

echo "PASS: first connection has no automatic GitHub dependency"
