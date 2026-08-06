#!/bin/bash
# Builds DeadAir.app. Pass --install to also copy it into ~/Applications.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DeadAir"
BUNDLE_ID="nu.soep.deadair"
CONFIG="release"
APP="build/${APP_NAME}.app"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# iconutil wants its own size naming, so map the appiconset onto it.
if [[ -d Resources/AppIcon.appiconset ]]; then
	echo "==> Building AppIcon.icns"
	ICONSET="build/AppIcon.iconset"
	rm -rf "$ICONSET"
	mkdir -p "$ICONSET"
	SET=Resources/AppIcon.appiconset
	cp "$SET/icon_16.png" "$ICONSET/icon_16x16.png"
	cp "$SET/icon_32.png" "$ICONSET/icon_16x16@2x.png"
	cp "$SET/icon_32.png" "$ICONSET/icon_32x32.png"
	cp "$SET/icon_64.png" "$ICONSET/icon_32x32@2x.png"
	cp "$SET/icon_128.png" "$ICONSET/icon_128x128.png"
	cp "$SET/icon_256.png" "$ICONSET/icon_128x128@2x.png"
	cp "$SET/icon_256.png" "$ICONSET/icon_256x256.png"
	cp "$SET/icon_512.png" "$ICONSET/icon_256x256@2x.png"
	cp "$SET/icon_512.png" "$ICONSET/icon_512x512.png"
	cp "$SET/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
	iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Resources/MenuBar holds the designed template PNGs. They are the design source, not
# shipped assets: StatusIcon.swift draws the same marks as vectors, so they stay sharp
# at any size and need no @2x pair.

# Ad-hoc signature. A stable identifier keeps the bundle id consistent, but the
# code hash changes every build, so macOS may ask for Accessibility again.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

if [[ "${1:-}" == "--install" ]]; then
	DEST="$HOME/Applications/${APP_NAME}.app"
	echo "==> Installing to $DEST"
	osascript -e 'quit app "DeadAir"' 2>/dev/null || true
	rm -rf "$DEST"
	mkdir -p "$HOME/Applications"
	cp -R "$APP" "$DEST"
	open "$DEST"
	echo "==> Launched from $DEST"
else
	echo "==> Built $APP (run ./build.sh --install to install and launch)"
fi
