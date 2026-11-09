#!/bin/sh
# MornLiveUtil.app を作る (VERSION=1.2.3 で版を指定)
set -e
cd "$(dirname "$0")"
ARCH="--arch arm64 --arch x86_64"
swift build -c release $ARCH
APP=MornLiveUtil.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release $ARCH --show-bin-path)/MornLiveUtil" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MornLiveUtil</string>
<key>CFBundleIdentifier</key><string>com.matsufriends.MornLiveUtil</string>
<key>CFBundleName</key><string>MornLiveUtil</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-0.0.0}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
echo "$APP"
