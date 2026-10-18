#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Lifting
app="${1:-../Lifting Preview.app}"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Lifting "$app/Contents/MacOS/Lifting"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Lifting</string>
<key>CFBundleIdentifier</key><string>local.lifting.preview</string>
<key>CFBundleName</key><string>Lifting Preview</string>
<key>CFBundleDisplayName</key><string>Lifting</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
printf '%s\n' "$app"
