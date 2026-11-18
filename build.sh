#!/bin/bash
# Builds "Twist Caller.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP="Twist Caller.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library main.swift -o "$APP/Contents/MacOS/TwistCaller"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Twist Caller</string>
    <key>CFBundleDisplayName</key><string>Twist Caller</string>
    <key>CFBundleIdentifier</key><string>local.twistcaller</string>
    <key>CFBundleExecutable</key><string>TwistCaller</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Twist Caller listens for voice commands like "next" and "stop".</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Twist Caller recognizes spoken commands like "next" and "stop".</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
