#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_PRODUCT="GitHubReady"
APP_DISPLAY_NAME="GitHub Ready"
BUNDLE_ID="com.githubready.app"
MIN_SYSTEM_VERSION="13.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_BINARY="$MACOS_DIR/$APP_PRODUCT"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SVG="$ROOT_DIR/Sources/GitHubReady/Resources/GitHubReadyIcon.svg"
STATUS_ICON_SVG="$ROOT_DIR/GitHub-Ready-Icon-white.svg"

swift_command() {
  /usr/bin/xcrun swift "$@"
}

stop_running_development_app() {
  /usr/bin/pkill -TERM -x "$APP_PRODUCT" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    if ! /usr/bin/pgrep -x "$APP_PRODUCT" >/dev/null 2>&1; then
      return
    fi
    /bin/sleep 0.2
  done
}

write_info_plist() {
  /bin/cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_PRODUCT</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>GitHubReadyIcon</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

copy_brand_assets() {
  if [[ ! -f "$ICON_SVG" ]]; then
    echo "Brand icon source not found: $ICON_SVG" >&2
    exit 1
  fi
  if [[ ! -f "$STATUS_ICON_SVG" ]]; then
    echo "Status icon source not found: $STATUS_ICON_SVG" >&2
    exit 1
  fi

  /bin/mkdir -p "$RESOURCES_DIR"
  /usr/bin/sips -s format png "$ICON_SVG" --out "$RESOURCES_DIR/GitHubReadyIcon.png" >/dev/null 2>&1
  /usr/bin/sips -s format png "$STATUS_ICON_SVG" --out "$RESOURCES_DIR/GitHubReadyStatusIcon.png" >/dev/null 2>&1

  local iconset="$DIST_DIR/GitHubReadyIcon.iconset"
  /bin/rm -rf "$iconset"
  /bin/mkdir -p "$iconset"
  local -a entries=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
  )
  local entry pixels filename
  for entry in "${entries[@]}"; do
    pixels="${entry%%:*}"
    filename="${entry#*:}"
    /usr/bin/sips -z "$pixels" "$pixels" "$RESOURCES_DIR/GitHubReadyIcon.png" --out "$iconset/$filename" >/dev/null 2>&1
  done
  /usr/bin/iconutil -c icns "$iconset" -o "$RESOURCES_DIR/GitHubReadyIcon.icns"
  /bin/rm -rf "$iconset"
}

build_bundle() {
  cd "$ROOT_DIR"
  swift_command build --product "$APP_PRODUCT"
  local build_binary
  build_binary="$(swift_command build --show-bin-path)/$APP_PRODUCT"
  if [[ ! -x "$build_binary" ]]; then
    echo "Built executable not found: $build_binary" >&2
    exit 1
  fi

  /bin/rm -rf "$APP_BUNDLE"
  /bin/mkdir -p "$MACOS_DIR"
  /bin/cp "$build_binary" "$APP_BINARY"
  /bin/chmod 0755 "$APP_BINARY"
  copy_brand_assets
  write_info_plist

  /usr/bin/plutil -lint "$INFO_PLIST"
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"
  echo "Built $APP_BUNDLE"
}

verify_bundle() {
  build_bundle
  /usr/bin/plutil -lint "$INFO_PLIST"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

  stop_running_development_app
  /usr/bin/open -n "$APP_BUNDLE"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if /usr/bin/pgrep -x "$APP_PRODUCT" >/dev/null 2>&1; then
      echo "Smoke process check passed: $APP_PRODUCT is running"
      return
    fi
    /bin/sleep 0.5
  done
  echo "Smoke process check failed: $APP_PRODUCT did not start" >&2
  exit 1
}

case "$MODE" in
  build)
    build_bundle
    ;;
  verify)
    verify_bundle
    ;;
  run)
    build_bundle
    stop_running_development_app
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
  clean)
    stop_running_development_app
    /bin/rm -rf "$ROOT_DIR/.build" "$DIST_DIR"
    echo "Removed generated .build and dist directories"
    ;;
  *)
    echo "usage: $0 [build|verify|run|clean]" >&2
    exit 2
    ;;
esac
