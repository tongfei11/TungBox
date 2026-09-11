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
TARGET_ARCH="${1:-${TARGET_ARCH:-$(uname -m)}}"

case "$TARGET_ARCH" in
  arm64)
    ARCH_SUFFIX="arm64"
    TARGET_ARCHS=(arm64)
    ;;
  x86_64|amd64)
    TARGET_ARCH="x86_64"
    ARCH_SUFFIX="x86_64"
    TARGET_ARCHS=(x86_64)
    ;;
  universal)
    ARCH_SUFFIX="universal"
    TARGET_ARCHS=(arm64 x86_64)
    ;;
  *)
    echo "Unsupported target architecture: $TARGET_ARCH" >&2
    echo "Supported values: arm64, x86_64, universal" >&2
    exit 1
    ;;
esac

RELEASE_VERSION="$(awk -F'"' '/static let release/ { print $2; exit }' Sources/TungBox/Core/AppMetadata.swift)"
BUILD_NUMBER="$(awk -F'"' '/static let build/ { print $2; exit }' Sources/TungBox/Core/AppMetadata.swift)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

binary_supports_arch() {
  local binary="$1"
  local expected_arch="$2"
  local archs

  archs="$(lipo -archs "$binary" 2>/dev/null || true)"
  [[ -n "$archs" ]] && grep -qw "$expected_arch" <<<"$archs"
}

binary_supports_target() {
  local binary="$1"
  local arch

  for arch in "${TARGET_ARCHS[@]}"; do
    if ! binary_supports_arch "$binary" "$arch"; then
      return 1
    fi
  done
}

go_arch_for() {
  local target_arch="$1"

  case "$target_arch" in
    arm64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *)
      echo "Unsupported Go target architecture: $target_arch" >&2
      return 1
      ;;
  esac
}

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
  local target_arch="$1"
  local go_arch
  go_arch="$(go_arch_for "$target_arch")"

  if [[ -n "${TUNGBOX_CORE_PATH:-}" && -x "$TUNGBOX_CORE_PATH" ]]; then
    if ! binary_supports_arch "$TUNGBOX_CORE_PATH" "$target_arch"; then
      echo "Provided TUNGBOX_CORE_PATH does not contain architecture: $target_arch" >&2
      return 1
    fi
    printf '%s\n' "$TUNGBOX_CORE_PATH"
    return 0
  fi

  local patched_core="$ROOT_DIR/.build/patched-core/sing-box"
  if [[ -x "$patched_core" ]]; then
    if binary_supports_arch "$patched_core" "$target_arch"; then
      echo "Using local patched sing-box Core: $patched_core" >&2
      printf '%s\n' "$patched_core"
      return 0
    fi
    echo "Skipping local patched sing-box Core because it does not contain architecture: $target_arch" >&2
  fi

  if ! command -v go >/dev/null 2>&1; then
    echo "Missing Go toolchain. Install Go or set TUNGBOX_CORE_PATH to a pre-built core." >&2
    return 1
  fi

  local gopath
  gopath="$(go env GOPATH)"
  local host_goarch
  host_goarch="$(go env GOARCH)"

  # Resolve latest sing-box version for version injection
  local core_version
  if core_version="$(go list -m -json github.com/sagernet/sing-box@latest 2>/dev/null | awk -F'"' '/"Version"/ {print $4}')" && [[ -n "$core_version" ]]; then
    echo "sing-box ${core_version} identified, building..." >&2
  else
    core_version="unknown"
    echo "Failed to resolve sing-box version, building with 'unknown'..." >&2
  fi

  local tags="with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale"
  local ldflags="-X 'github.com/sagernet/sing-box/constant.Version=${core_version}' -s -w -buildid="
  local output_dir="$ROOT_DIR/.build/core/${target_arch}"
  local binary="$output_dir/sing-box"
  local installed_binary="$gopath/bin/sing-box"
  if [[ "$go_arch" != "$host_goarch" ]]; then
    installed_binary="$gopath/bin/darwin_${go_arch}/sing-box"
  fi
  mkdir -p "$output_dir"

  echo "Building stripped sing-box core for ${target_arch} (tags: ${tags}, version: ${core_version})..." >&2
  env CGO_ENABLED=0 GOOS=darwin GOARCH="$go_arch" go install \
    -trimpath -ldflags="$ldflags" -tags "$tags" github.com/sagernet/sing-box/cmd/sing-box@latest

  if [[ -x "$installed_binary" ]]; then
    cp "$installed_binary" "$binary"
    chmod +x "$binary"
  fi

  if [[ -x "$binary" ]] && binary_supports_arch "$binary" "$target_arch"; then
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

build_app_binary() {
  local target_arch="$1"

  echo "Building ${PRODUCT} ${RELEASE_VERSION}(${BUILD_NUMBER}) for ${target_arch}..."
  swift build -c release --arch "$target_arch" --product "$PRODUCT"
  LAST_BIN_DIR="$(swift build -c release --arch "$target_arch" --show-bin-path)"
  LAST_BINARY_PATH="$LAST_BIN_DIR/$PRODUCT"
  LAST_RESOURCE_BUNDLE="$LAST_BIN_DIR/${PRODUCT}_${PRODUCT}.bundle"

  if ! binary_supports_arch "$LAST_BINARY_PATH" "$target_arch"; then
    echo "Built app binary does not contain architecture: $target_arch" >&2
    exit 1
  fi
}

prepare_app_binary() {
  local resource_bundle_source=""

  if [[ "$TARGET_ARCH" == "universal" ]]; then
    local arm_binary="$WORK_DIR/${PRODUCT}-arm64"
    local x86_binary="$WORK_DIR/${PRODUCT}-x86_64"
    local universal_binary="$WORK_DIR/${PRODUCT}-universal"

    build_app_binary arm64
    cp "$LAST_BINARY_PATH" "$arm_binary"
    resource_bundle_source="$LAST_RESOURCE_BUNDLE"

    build_app_binary x86_64
    cp "$LAST_BINARY_PATH" "$x86_binary"

    lipo -create -output "$universal_binary" "$arm_binary" "$x86_binary"
    cp "$universal_binary" "$MACOS_DIR/$PRODUCT"
  else
    build_app_binary "$TARGET_ARCH"
    resource_bundle_source="$LAST_RESOURCE_BUNDLE"
    cp "$LAST_BINARY_PATH" "$MACOS_DIR/$PRODUCT"
  fi

  chmod +x "$MACOS_DIR/$PRODUCT"

  if ! binary_supports_target "$MACOS_DIR/$PRODUCT"; then
    echo "Built app binary does not contain expected architectures: ${TARGET_ARCHS[*]}" >&2
    exit 1
  fi

  if [[ -d "$resource_bundle_source" ]]; then
    cp -R "$resource_bundle_source" "$RESOURCES_DIR/"
  fi
}

prepare_core() {
  if [[ "$TARGET_ARCH" == "universal" ]]; then
    local arm_core
    local x86_core
    local universal_core="$WORK_DIR/sing-box-universal"

    arm_core="$(build_core arm64)"
    x86_core="$(build_core x86_64)"
    lipo -create -output "$universal_core" "$arm_core" "$x86_core"
    cp "$universal_core" "$CORE_DIR/sing-box"
  else
    local core_path
    core_path="$(build_core "$TARGET_ARCH")"
    cp "$core_path" "$CORE_DIR/sing-box"
    echo "Bundled sing-box Core: $core_path"
  fi

  chmod +x "$CORE_DIR/sing-box"

  if ! binary_supports_target "$CORE_DIR/sing-box"; then
    echo "Bundled sing-box Core does not contain expected architectures: ${TARGET_ARCHS[*]}" >&2
    exit 1
  fi

  echo "Bundled sing-box Core: $CORE_DIR/sing-box"
}

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CORE_DIR"

prepare_app_binary
prepare_core

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

DMG_NAME="${PRODUCT}-${RELEASE_VERSION}-macos-${ARCH_SUFFIX}"
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
