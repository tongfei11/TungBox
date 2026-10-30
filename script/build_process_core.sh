#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:?Usage: build_process_core.sh /absolute/output/sing-box}"
case "$OUTPUT" in
  /*) ;;
  *) echo "Output must be an absolute path" >&2; exit 1 ;;
esac
if [[ "$(uname -s)" != Darwin ]]; then
  echo "The process lookup patch requires macOS and libproc" >&2
  exit 1
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SOURCE="$(go mod download -json github.com/sagernet/sing-box@v1.14.4 | python3 -c 'import json,sys; print(json.load(sys.stdin)["Dir"])')"
cp -R "$SOURCE/." "$WORK/"
chmod -R u+w "$WORK"
cp "$ROOT"/script/core-process-fallback/* "$WORK/common/process/"
python3 - "$WORK/common/process/searcher_darwin.go" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
old='return FindDarwinConnectionOwner(network, source, destination)'
assert s.count(old)==1
s=s.replace(old,'''owner, err := FindDarwinConnectionOwner(network, source, destination)
 if err == ErrNotFound { return findDarwinProcessByFD(ctx, network, source, destination) }
 return owner, err''')
p.write_text(s)
PY
cd "$WORK"
export CGO_ENABLED=1
TAGS="with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api"
gofmt -w common/process/fallback*.go common/process/searcher_darwin.go
go test ./common/process
go build -tags "$TAGS" -trimpath -ldflags '-X github.com/sagernet/sing-box/constant.Version=1.14.4-tungbox.1' -o "$OUTPUT" ./cmd/sing-box
codesign -f -s - "$OUTPUT"
"$OUTPUT" version
