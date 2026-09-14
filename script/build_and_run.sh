#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WorkCloseout"
BUNDLE_ID="local.workcloseout.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
CONFIG_SOURCE="${WORK_CLOSEOUT_CONFIG:-}"

swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"
[[ "$CONFIG_SOURCE" = /* && -f "$CONFIG_SOURCE" ]] || { echo "Set WORK_CLOSEOUT_CONFIG to an existing absolute profile path before launching Work Closeout" >&2; exit 2; }
cp "$CONFIG_SOURCE" "$APP_RESOURCES/work-closeout.json"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0"><dict>' "<key>CFBundleExecutable</key><string>$APP_NAME</string>" "<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>" "<key>CFBundleName</key><string>$APP_NAME</string>" '<key>CFBundlePackageType</key><string>APPL</string>' '<key>LSMinimumSystemVersion</key><string>14.0</string>' '<key>NSPrincipalClass</key><string>NSApplication</string>' '</dict></plist>' > "$APP_CONTENTS/Info.plist"

case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug|debug) lldb -- "$APP_MACOS/$APP_NAME" ;;
  --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
