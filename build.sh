#!/bin/bash
# Builds "Twist Caller.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP="Twist Caller.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# App icon
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift icon.swift "$ICONSET/base.png"
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
cp "$ICONSET/base.png" AppIcon.png
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -parse-as-library main.swift -o "$APP/Contents/MacOS/TwistCaller"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Twist Caller</string>
    <key>CFBundleDisplayName</key><string>Twist Caller</string>
    <key>CFBundleIdentifier</key><string>local.twistcaller</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

# Sign with this Mac's code-signing certificate when there is one, so macOS
# keeps the microphone/speech permissions across rebuilds. Otherwise ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning | awk '/^ *1\)/ {print $2}')"
if [ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" "$APP"; then
    echo "Signed with certificate $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc"
fi
echo "Built $APP"
