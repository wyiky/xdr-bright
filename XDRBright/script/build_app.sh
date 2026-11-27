#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
APP_NAME="XDRBright"
DISPLAY_NAME="XDR Bright"
BUNDLE_ID="local.xdrbright.app"
APP_VERSION="1.0.0"
BUILD_VERSION="1"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
INSTALLED_BUNDLE="/Applications/$DISPLAY_NAME.app"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

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
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

package_app() {
  swift build --package-path "$ROOT_DIR" -c release
  local build_dir
  build_dir="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"
  local build_binary="$build_dir/$APP_NAME"
  [ -x "$build_binary" ] || { echo "build output missing: $build_binary" >&2; exit 1; }

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
  cp "$build_binary" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  [ -f "$ICON_FILE" ] && cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  write_info_plist "$APP_BUNDLE/Contents/Info.plist"
  plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

  # 临时签名，便于本机直接运行；对外分发需要接收方右键打开或去 quarantine。
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
  codesign --verify --deep --strict "$APP_BUNDLE"

  rm -f "$DIST_DIR/XDR-Bright.zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/XDR-Bright.zip"
  echo "Built: $APP_BUNDLE"
  echo "Zip:   $DIST_DIR/XDR-Bright.zip"
}

case "$MODE" in
  build|"")
    package_app
    ;;
  install)
    package_app
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    rm -rf "$INSTALLED_BUNDLE"
    ditto "$APP_BUNDLE" "$INSTALLED_BUNDLE"
    codesign --verify --deep --strict "$INSTALLED_BUNDLE"
    open -a "$INSTALLED_BUNDLE"
    echo "Installed: $INSTALLED_BUNDLE"
    ;;
  *)
    echo "usage: $0 [build|install]" >&2
    exit 2
    ;;
esac
