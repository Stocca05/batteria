#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p bin

# CLI
clang -O2 -fobjc-arc -o bin/batteria src/batteria.m -framework Foundation -framework IOKit

# App menu bar
APP="bin/Batteria.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Batteria</string>
	<key>CFBundleIdentifier</key><string>local.batteria</string>
	<key>CFBundleName</key><string>Batteria</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.4</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
clang -O2 -fobjc-arc -o "$APP/Contents/MacOS/Batteria" src/BatteriaApp.m -framework Cocoa -framework IOKit

echo "Build OK:"
echo "  bin/batteria        (CLI)"
echo "  $APP  (app menu bar)"
