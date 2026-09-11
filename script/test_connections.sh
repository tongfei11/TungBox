#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Sources/TungBox/main.swift').read_text()
source = source[:source.rindex('\nlet app = NSApplication.shared')]
Path(sys.argv[1]).write_text(source + '\n' + Path('script/connection-regressions/main.swift').read_text())
PY
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources/TungBox -name '*.swift' ! -name main.swift)
swiftc "${sources[@]}" "$TEST_DIR/main.swift" -o "$TEST_DIR/connections"
"$TEST_DIR/connections"
