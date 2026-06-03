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
PINNED_CORE_VERSION="${TUNGBOX_CORE_VERSION:-v1.13.12}"

clear_finder_info() {
  command -v xattr >/dev/null 2>&1 || return 0

  local attempt
  for attempt in 1 2 3 4 5; do
    while IFS= read -r -d '' item; do
      xattr -c "$item" 2>/dev/null || true
      xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
      xattr -d com.apple.macl "$item" 2>/dev/null || true
      xattr -d 'com.apple.fileprovider.fpfs#P' "$item" 2>/dev/null || true
      xattr -d com.apple.quarantine "$item" 2>/dev/null || true
    done < <(find "$APP_DIR" -depth -print0)

    xattr -c "$APP_DIR" 2>/dev/null || true
    xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
    xattr -d com.apple.macl "$APP_DIR" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
    xattr -d com.apple.quarantine "$APP_DIR" 2>/dev/null || true

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

build_core() {
  if [[ -n "${TUNGBOX_CORE_PATH:-}" && -x "$TUNGBOX_CORE_PATH" ]]; then
    printf '%s\n' "$TUNGBOX_CORE_PATH"
    return 0
  fi

  if ! command -v go >/dev/null 2>&1; then
    echo "Missing Go toolchain. Install Go or set TUNGBOX_CORE_PATH to a pre-built core." >&2
    return 1
  fi

  local gopath
  gopath="$(go env GOPATH)"

  # Release builds pin the core version for reproducible artifacts.
  local core_version
  if core_version="$(go list -m -json "github.com/sagernet/sing-box@${PINNED_CORE_VERSION}" 2>/dev/null | awk -F'"' '/"Version"/ {print $4}')" && [[ -n "$core_version" ]]; then
    echo "sing-box ${core_version} identified, building..." >&2
  else
    echo "Failed to resolve pinned sing-box version: ${PINNED_CORE_VERSION}" >&2
    return 1
  fi

  local tags="with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale"
  local ldflags="-X 'github.com/sagernet/sing-box/constant.Version=${core_version}' -s -w -buildid="
  echo "Building stripped sing-box core (tags: ${tags}, version: ${core_version})..." >&2
  env CGO_ENABLED=0 go install -ldflags="$ldflags" -tags "$tags" \
    "github.com/sagernet/sing-box/cmd/sing-box@${core_version}"

  local binary="$gopath/bin/sing-box"

  if [[ -x "$binary" ]]; then
    printf '%s\n' "$binary"
    return 0
  fi

  echo "Core build failed unexpectedly." >&2
  return 1
}

generate_app_icon() {
  local logo="$ROOT_DIR/Sources/TungBox/Resources/Tray/logo.png"
  local icon_set_dir="/tmp/${PRODUCT}_AppIcon.iconset"
  local icns_path="$RESOURCES_DIR/AppIcon.icns"

  rm -rf "$icon_set_dir"
  mkdir -p "$icon_set_dir"

  local sizes=(16 32 128 256 512)
  local size
  for size in "${sizes[@]}"; do
    sips -z "$size" "$size" "$logo" --out "$icon_set_dir/icon_${size}x${size}.png" &>/dev/null
    sips -z "$((size*2))" "$((size*2))" "$logo" --out "$icon_set_dir/icon_${size}x${size}@2x.png" &>/dev/null
  done
  # 1024x1024 for @2x of 512
  sips -z 1024 1024 "$logo" --out "$icon_set_dir/icon_512x512@2x.png" &>/dev/null

  iconutil -c icns "$icon_set_dir" -o "$icns_path" 2>/dev/null
  rm -rf "$icon_set_dir"

  if [[ -f "$icns_path" ]]; then
    echo "Generated app icon: $icns_path"
    return 0
  fi
  echo "Warning: failed to generate .icns, app will use default icon." >&2
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

if CORE_PATH="$(build_core)"; then
  cp "$CORE_PATH" "$CORE_DIR/sing-box"
  chmod +x "$CORE_DIR/sing-box"
  echo "Bundled sing-box Core: $CORE_PATH"
else
  echo "Missing sing-box Core. Set TUNGBOX_CORE_PATH to a pre-built binary, or install Go toolchain." >&2
  exit 1
fi

generate_app_icon

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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

DMG_NAME="${PRODUCT}-${RELEASE_VERSION}-macos-arm64"
DMG_PATH="$ROOT_DIR/dist/${DMG_NAME}.dmg"

echo "Creating DMG: ${DMG_NAME}.dmg..."
DMG_TEMP=$(mktemp -d)
ln -sf /Applications "$DMG_TEMP/Applications"
ditto --noextattr --noqtn "$APP_DIR" "$DMG_TEMP/${PRODUCT}.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$DMG_TEMP/${PRODUCT}.app"

hdiutil create \
  -volname "${PRODUCT}" \
  -srcfolder "$DMG_TEMP" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

rm -rf "$DMG_TEMP"

if [[ -f "$DMG_PATH" ]]; then
  echo "Created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
  shasum -a 256 "$DMG_PATH" | awk '{print $1}' > "${DMG_PATH}.sha256"
  echo "SHA256: $(cat "${DMG_PATH}.sha256")"

  # Clean up old zip
  rm -f "$ROOT_DIR/dist/${DMG_NAME}.zip" "$ROOT_DIR/dist/${DMG_NAME}.zip.sha256"
fi

# hdiutil/Finder can attach metadata to the working app after the release image is
# created. Clean and re-sign the local copy so follow-up verification stays green.
clear_finder_info
sign_app
verify_signature

echo "Packaged: $APP_DIR"
