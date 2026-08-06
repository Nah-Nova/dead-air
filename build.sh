#!/bin/bash
# Builds DeadAir.app.
#   --install   also copy it into ~/Applications and launch it
#   --release   build a universal binary and zip it for distribution
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DeadAir"
BUNDLE_ID="nu.soep.deadair"
CONFIG="release"
APP="build/${APP_NAME}.app"
MODE="${1:-}"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

# A universal binary needs two passes and lipo. SPM's own --arch wants xcbuild, which
# only ships with full Xcode, and this project builds on Command Line Tools alone.
if [[ "$MODE" == "--release" ]]; then
	echo "==> Compiling x86_64 slice"
	swift build -c "$CONFIG" --scratch-path .build-x86 \
		-Xswiftc -target -Xswiftc x86_64-apple-macos15.0 \
		-Xcc -target -Xcc x86_64-apple-macos15.0
	echo "==> Merging into a universal binary"
	mkdir -p build
	lipo -create "$BIN" ".build-x86/${CONFIG}/${APP_NAME}" -output "build/${APP_NAME}-universal"
	BIN="build/${APP_NAME}-universal"
	lipo -archs "$BIN"
fi

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

if [[ "$MODE" == "--release" ]]; then
	VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
	ZIP="build/${APP_NAME}-${VERSION}-universal.zip"
	echo "==> Zipping $ZIP"
	rm -f "$ZIP"
	# ditto rather than zip, so the bundle's signature and symlinks survive the round trip.
	ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
	shasum -a 256 "$ZIP"
	echo "==> Release archive ready. It is ad-hoc signed and NOT notarised, so a downloader"
	echo "    has to clear quarantine. See the README."
	exit 0
fi

if [[ "$MODE" == "--install" ]]; then
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
