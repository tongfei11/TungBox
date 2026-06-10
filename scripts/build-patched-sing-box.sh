#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="${TMPDIR:-/tmp}/tungbox-sing-box-build"
SING_BOX_REF="${SING_BOX_REF:-8a42af329c6f8cc2c43a142ea4eadecd5412bfce}"
SING_TUN_REF="${SING_TUN_REF:-6e76db79f94a}"
OUTPUT="${OUTPUT:-$ROOT_DIR/.build/patched-core/sing-box}"
TAGS="${TAGS:-with_gvisor,with_clash_api,with_quic,with_utls,with_wireguard}"
VERSION="${VERSION:-1.14.0-alpha.29-tungbox-tun0126}"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

git clone https://github.com/SagerNet/sing-box.git "$WORK_DIR/sing-box"
git -C "$WORK_DIR/sing-box" checkout "$SING_BOX_REF"

git clone https://github.com/SagerNet/sing-tun.git "$WORK_DIR/sing-tun"
git -C "$WORK_DIR/sing-tun" checkout "$SING_TUN_REF"
git -C "$WORK_DIR/sing-tun" apply "$ROOT_DIR/CorePatches/sing-tun-macos-safe-routing.patch"

go -C "$WORK_DIR/sing-box" mod edit -replace github.com/sagernet/sing-tun="$WORK_DIR/sing-tun"
mkdir -p "$(dirname "$OUTPUT")"
go -C "$WORK_DIR/sing-box" build -tags "$TAGS" -ldflags "-X github.com/sagernet/sing-box/constant.Version=$VERSION" -o "$OUTPUT" ./cmd/sing-box
chmod 755 "$OUTPUT"

"$OUTPUT" version
shasum -a 256 "$OUTPUT"
