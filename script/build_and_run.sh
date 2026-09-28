#!/usr/bin/env bash
# Build, sign, package, and optionally launch Reflect.
# Usage:
#   ./script/build_and_run.sh          # build, package, launch
#   ./script/build_and_run.sh --verify # build + tests + package checks, no launch
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUTS_DIR="$(cd "$ROOT/.." && pwd)"
cd "$ROOT"

MODE="run"
if [[ "${1:-}" == "--verify" ]]; then MODE="verify"; fi

APP_NAME="Reflect"
APP_STAGE_ROOT="${TMPDIR:-/tmp}/Reflect-build-$(id -u)"
APP_STAGE="$APP_STAGE_ROOT/$APP_NAME.app"
ZIP_PATH="$OUTPUTS_DIR/Reflect-macOS.zip"

echo "==> swift build (release)"
swift build -c release --product Reflect

echo "==> Staging signed app in $APP_STAGE"
rm -rf "$APP_STAGE"
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
cp "$BIN_PATH" "$APP_STAGE/Contents/MacOS/$APP_NAME"

cat > "$APP_STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.reflect.Reflect</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP_STAGE/Contents/PkgInfo"

# Sign outside the synced output folder so File Provider metadata cannot alter
# the bundle signature. The archive is the user-facing app deliverable.
xattr -cr "$APP_STAGE" 2>/dev/null || true
codesign --force --sign - "$APP_STAGE"
codesign --verify --strict "$APP_STAGE"

echo "==> Packaging $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --keepParent "$APP_STAGE" "$ZIP_PATH"

if [[ "$MODE" == "verify" ]]; then
    echo "==> swift test"
    swift test

    echo "==> reflect-test-runner (authoritative core suite)"
    swift run -c debug reflect-test-runner > /dev/null

    echo "==> Verifying app and archive"
    plutil -lint "$APP_STAGE/Contents/Info.plist"
    codesign --verify --strict "$APP_STAGE"
    ARCHIVE_CHECK="$(mktemp -d)"
    ditto -x -k "$ZIP_PATH" "$ARCHIVE_CHECK"
    codesign --verify --strict "$ARCHIVE_CHECK/$APP_NAME.app"
    test -x "$ARCHIVE_CHECK/$APP_NAME.app/Contents/MacOS/$APP_NAME"
    rm -rf "$ARCHIVE_CHECK"
    echo "VERIFY OK: $ZIP_PATH"
    exit 0
fi

echo "==> Stopping a previous Reflect instance"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "==> Launching $APP_NAME"
/usr/bin/open -n "$APP_STAGE"
echo "Launched $APP_NAME. App archive: $ZIP_PATH"
