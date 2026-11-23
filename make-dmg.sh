#!/bin/sh
# MornLiveUtil.app から、アプリと /Applications へのリンクを並べた MornLiveUtil.dmg を作る
set -e
cd "$(dirname "$0")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto MornLiveUtil.app "$STAGE/MornLiveUtil.app"
ln -s /Applications "$STAGE/Applications"
rm -f MornLiveUtil.dmg
hdiutil create -volname MornLiveUtil -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov MornLiveUtil.dmg >/dev/null
echo MornLiveUtil.dmg
