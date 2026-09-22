#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/core_version.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir "$TEST_DIR/with space"

cat > "$TEST_DIR/with space/correct" <<'EOF'
#!/bin/sh
echo 'sing-box version v1.14.0'
EOF
cat > "$TEST_DIR/stale" <<'EOF'
#!/bin/sh
echo 'sing-box version v1.13.14'
EOF
chmod +x "$TEST_DIR/with space/correct" "$TEST_DIR/stale"

verify_core_version "$TEST_DIR/with space/correct" "1.14.0"
if verify_core_version "$TEST_DIR/stale" "1.14.0" >/dev/null 2>&1; then
  echo "FAIL: stale core was accepted" >&2
  exit 1
fi

echo "PASS: core version verification"
