#!/bin/sh
# MornLiveUtil.app を作る
set -e
cd "$(dirname "$0")"
swift build -c release
APP=MornLiveUtil.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/MornLiveUtil "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MornLiveUtil</string>
<key>CFBundleIdentifier</key><string>com.matsufriends.MornLiveUtil</string>
<key>CFBundleName</key><string>MornLiveUtil</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
echo "$APP"
