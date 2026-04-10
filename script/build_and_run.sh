#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WhisperForMac"
BUNDLE_ID="com.rene.whisperformac"
MIN_SYSTEM_VERSION="15.0"
ARM64_TRIPLE="arm64-apple-macosx15.0"
INTEL_TRIPLE="x86_64-apple-macosx15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ROOT="$ROOT_DIR/.build/distribution"
APP_ICON_CATALOG="$ROOT_DIR/Sources/WhisperForMac/Resources/AppIcons/Assets.xcassets"
GENERATED_ICON_DIR="$BUILD_ROOT/AppIconAssets"
GENERATED_ICNS="$GENERATED_ICON_DIR/AppIcon.icns"
GENERATED_ASSETS_CAR="$GENERATED_ICON_DIR/Assets.car"
GENERATED_ICON_INFO_PLIST="$GENERATED_ICON_DIR/partial-info.plist"
ARM64_SCRATCH="$BUILD_ROOT/arm64"
INTEL_SCRATCH="$BUILD_ROOT/x86_64"
ARM64_APP_BUNDLE="$DIST_DIR/${APP_NAME}-AppleSilicon.app"
INTEL_APP_BUNDLE="$DIST_DIR/${APP_NAME}-Intel.app"
UNIVERSAL_APP_BUNDLE="$DIST_DIR/${APP_NAME}-Universal.app"
DEFAULT_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$DEFAULT_APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

build_arch() {
  local scratch_path="$1"
  local triple="$2"

  swift build \
    --scratch-path "$scratch_path" \
    --triple "$triple"
}

bin_path_for() {
  local scratch_path="$1"
  local triple="$2"

  swift build \
    --scratch-path "$scratch_path" \
    --triple "$triple" \
    --show-bin-path
}

resource_path_for() {
  local bin_dir="$1"
  echo "$bin_dir/${APP_NAME}_${APP_NAME}.resources"
}

write_info_plist() {
  local info_plist="$1"

  cat >"$info_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

generate_app_icon() {
  if [ ! -d "$APP_ICON_CATALOG" ]; then
    return
  fi

  rm -rf "$GENERATED_ICON_DIR"
  mkdir -p "$GENERATED_ICON_DIR"

  xcrun actool "$APP_ICON_CATALOG" \
    --compile "$GENERATED_ICON_DIR" \
    --platform macosx \
    --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$GENERATED_ICON_INFO_PLIST" \
    >/dev/null
}

stage_bundle() {
  local bundle_path="$1"
  local binary_path="$2"
  local resources_path="$3"

  local bundle_contents="$bundle_path/Contents"
  local bundle_macos="$bundle_contents/MacOS"
  local bundle_resources="$bundle_contents/Resources"

  rm -rf "$bundle_path"
  mkdir -p "$bundle_macos" "$bundle_resources"
  cp "$binary_path" "$bundle_macos/$APP_NAME"
  chmod +x "$bundle_macos/$APP_NAME"

  if [ -d "$resources_path" ]; then
    cp -R "$resources_path/." "$bundle_resources/"
  fi

  if [ -f "$GENERATED_ICNS" ]; then
    cp "$GENERATED_ICNS" "$bundle_resources/AppIcon.icns"
  fi

  if [ -f "$GENERATED_ASSETS_CAR" ]; then
    cp "$GENERATED_ASSETS_CAR" "$bundle_resources/Assets.car"
  fi

  write_info_plist "$bundle_contents/Info.plist"
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
generate_app_icon

build_arch "$ARM64_SCRATCH" "$ARM64_TRIPLE"
build_arch "$INTEL_SCRATCH" "$INTEL_TRIPLE"

ARM64_BIN_DIR="$(bin_path_for "$ARM64_SCRATCH" "$ARM64_TRIPLE")"
INTEL_BIN_DIR="$(bin_path_for "$INTEL_SCRATCH" "$INTEL_TRIPLE")"
ARM64_BINARY="$ARM64_BIN_DIR/$APP_NAME"
INTEL_BINARY="$INTEL_BIN_DIR/$APP_NAME"
UNIVERSAL_BINARY="$DIST_DIR/$APP_NAME-universal"
ARM64_RESOURCES="$(resource_path_for "$ARM64_BIN_DIR")"
INTEL_RESOURCES="$(resource_path_for "$INTEL_BIN_DIR")"

lipo -create "$ARM64_BINARY" "$INTEL_BINARY" -output "$UNIVERSAL_BINARY"

stage_bundle "$ARM64_APP_BUNDLE" "$ARM64_BINARY" "$ARM64_RESOURCES"
stage_bundle "$INTEL_APP_BUNDLE" "$INTEL_BINARY" "$INTEL_RESOURCES"
stage_bundle "$UNIVERSAL_APP_BUNDLE" "$UNIVERSAL_BINARY" "$ARM64_RESOURCES"

rm -rf "$DEFAULT_APP_BUNDLE"
cp -R "$UNIVERSAL_APP_BUNDLE" "$DEFAULT_APP_BUNDLE"
rm -f "$UNIVERSAL_BINARY"

open_app() {
  /usr/bin/open -n "$DEFAULT_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
