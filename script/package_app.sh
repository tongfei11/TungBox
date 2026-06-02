#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PRODUCT="TungBox"
IDENTIFIER="com.tung.tungbox"
APP_DIR="$ROOT_DIR/dist/${PRODUCT}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CORE_DIR="$RESOURCES_DIR/Core"

RELEASE_VERSION="$(awk -F'"' '/static let release/ { print $2; exit }' Sources/TungBox/Core/AppMetadata.swift)"
BUILD_NUMBER="$(awk -F'"' '/static let build/ { print $2; exit }' Sources/TungBox/Core/AppMetadata.swift)"

clear_finder_info() {
  command -v xattr >/dev/null 2>&1 || return 0

  local attempt
  for attempt in 1 2 3 4 5; do
    xattr -cr "$APP_DIR" 2>/dev/null || true
    find "$APP_DIR" -depth -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
    xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true

    if ! xattr -lr "$APP_DIR" 2>/dev/null | grep -q "com.apple.FinderInfo"; then
      return 0
    fi
    sleep 0.2
  done
}

verify_signature() {
  local attempt
  for attempt in 1 2 3 4 5; do
    sleep 0.4
    clear_finder_info
    if /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/dev/null; then
      echo "$APP_DIR: valid on disk"
      echo "$APP_DIR: satisfies its Designated Requirement"
      return 0
    fi
  done

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
}

sign_app() {
  local attempt
  for attempt in 1 2 3 4 5; do
    clear_finder_info
    if /usr/bin/codesign --force --deep --sign - "$APP_DIR" 2>/dev/null; then
      echo "$APP_DIR: signed"
      return 0
    fi
    sleep 0.4
  done

  clear_finder_info
  /usr/bin/codesign --force --deep --sign - "$APP_DIR"
}

find_core() {
  if [[ -n "${TUNGBOX_CORE_PATH:-}" && -x "$TUNGBOX_CORE_PATH" ]]; then
    printf '%s\n' "$TUNGBOX_CORE_PATH"
    return 0
  fi

  local candidates=(
    "$HOME/Library/Application Support/TungBox/Core/sing-box"
    "/opt/homebrew/bin/sing-box"
    "/usr/local/bin/sing-box"
    "/usr/bin/sing-box"
    "/opt/homebrew/bin/singbox"
    "/usr/local/bin/singbox"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v sing-box >/dev/null 2>&1; then
    command -v sing-box
    return 0
  fi

  if command -v singbox >/dev/null 2>&1; then
    command -v singbox
    return 0
  fi

  return 1
}

echo "Building ${PRODUCT} ${RELEASE_VERSION}(${BUILD_NUMBER})..."
swift build -c release --product "$PRODUCT"
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/$PRODUCT"
RESOURCE_BUNDLE="$BIN_DIR/${PRODUCT}_${PRODUCT}.bundle"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CORE_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$PRODUCT"
chmod +x "$MACOS_DIR/$PRODUCT"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

if CORE_PATH="$(find_core)"; then
  cp "$CORE_PATH" "$CORE_DIR/sing-box"
  chmod +x "$CORE_DIR/sing-box"
  echo "Bundled sing-box Core: $CORE_PATH"
else
  echo "Missing sing-box Core. Set TUNGBOX_CORE_PATH or install/import Core before packaging." >&2
  exit 1
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT}</string>
  <key>CFBundleIdentifier</key>
  <string>${IDENTIFIER}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${PRODUCT}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${RELEASE_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

clear_finder_info

sign_app
verify_signature

echo "Packaged: $APP_DIR"
