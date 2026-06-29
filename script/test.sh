#!/bin/sh
# Run TungBox unit tests.
#
# 走 swift test，但强制 DEVELOPER_DIR 指向 Xcode（不是 CommandLineTools）。
# 系统默认 xcode-select 经常指着 /Library/Developer/CommandLineTools，CLT 没有
# XCTest，会报 "no such module 'XCTest'"。这里临时覆盖，不动全局设置，不用 sudo。
#
# 用法：./script/test.sh [filter]
#   ./script/test.sh                            # 全部
#   ./script/test.sh DNSConfigTests             # 单个 suite
#   ./script/test.sh DNSConfigTests/testParseDoH3   # 单个 case

set -e

XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if [ ! -d "$XCODE_DEVELOPER_DIR" ]; then
  echo "未找到 Xcode：$XCODE_DEVELOPER_DIR"
  echo "请装 Xcode（不是 Command Line Tools）后再跑。"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -n "$1" ]; then
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" swift test --filter "$1"
else
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" swift test
fi
