#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Torque -j 2 -Xswiftc -Osize
app="${1:-../Torque.app}"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Torque "$app/Contents/MacOS/Torque"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Torque</string>
<key>CFBundleIdentifier</key><string>local.lifting.preview</string>
<key>CFBundleName</key><string>Torque</string>
<key>CFBundleDisplayName</key><string>Torque</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
printf '%s\n' "$app"
