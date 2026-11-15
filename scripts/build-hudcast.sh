#!/bin/sh
# Builds HudCast.app, the Mac side of TheHud's desktop panel.
#
# An app bundle rather than the bare binary because macOS grants Screen Recording and
# Accessibility to an app: run from Terminal, the permissions would land on Terminal instead.
# Signed ad hoc, which is enough to run it on this Mac. Right-click > Open the first time.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product hudcast
APP="dist/HudCast.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/hudcast "$APP/Contents/MacOS/HudCast"

# The phone app's sunglasses, cut to the Mac's icon shape.
ICONSET=".build/HudCast.iconset"
swift scripts/hudcast-icon.swift App/TheHud/Assets.xcassets/AppIcon.appiconset/AppIcon.png "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/HudCast.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.rimorcosmicam.hudcast</string>
	<key>CFBundleName</key>
	<string>HudCast</string>
	<key>CFBundleDisplayName</key>
	<string>HudCast</string>
	<key>CFBundleIconFile</key>
	<string>HudCast</string>
	<key>CFBundleExecutable</key>
	<string>HudCast</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<!-- A menu bar app: no Dock icon, no window. -->
	<key>LSUIElement</key>
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>HudCast streams this Mac to TheHud on your iPhone over your local network.</string>
	<key>NSBonjourServices</key>
	<array>
		<string>_thehud._tcp</string>
	</array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
(cd dist && rm -f HudCast.zip && ditto -c -k --keepParent HudCast.app HudCast.zip)
echo "built $APP and dist/HudCast.zip"
