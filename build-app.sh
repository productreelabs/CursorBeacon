#!/bin/bash
# Builds CursorBeacon.app for both Intel and Apple Silicon Macs, plus a zip for a GitHub release.
# Everything ends up in dist/. Usage: ./build-app.sh

set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(sed -n 's/^let appVersion = "\(.*\)"/\1/p' Sources/CursorBeacon/main.swift)
APP=dist/CursorBeacon.app
ZIP=dist/CursorBeacon-$VERSION.zip

echo "==> Building CursorBeacon $VERSION"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# One build per architecture, then combine them into a single universal binary.
for arch in arm64 x86_64; do
    swift build -c release --arch "$arch"
done
lipo -create -output "$APP/Contents/MacOS/CursorBeacon" \
    .build/arm64-apple-macosx/release/CursorBeacon \
    .build/x86_64-apple-macosx/release/CursorBeacon

echo "==> Drawing the icon"
swiftc -O scripts/make-icon.swift -o .build/make-icon
.build/make-icon dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf dist/AppIcon.iconset

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CursorBeacon</string>
    <key>CFBundleDisplayName</key>
    <string>CursorBeacon</string>
    <key>CFBundleIdentifier</key>
    <string>me.malikrasaq.cursorbeacon</string>
    <key>CFBundleExecutable</key>
    <string>CursorBeacon</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
EOF
plutil -lint "$APP/Contents/Info.plist" > /dev/null

echo "==> Signing (ad hoc) and zipping"
# Ad hoc signing is free and lets the app run on Apple Silicon. It isn't notarized,
# so macOS asks people to confirm the first launch (see the README).
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

# The release notes are this version's section of the changelog.
awk -v version="## $VERSION" '$0 == version { found = 1; next } found && /^## / { exit } found' CHANGELOG.md \
    | sed '/./,$!d' > dist/release-notes.md

echo
echo "Done:"
echo "  $APP"
echo "  $ZIP"
echo "  dist/release-notes.md"
