#!/bin/bash
# シミュレータで起動する(Mac 用)。xcodegen → ビルド → iPhone のシミュレータを起動 → インストール → 起動。
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate >/dev/null
DEVICE="${1:-iPhone 16}"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcodebuild -project Neochi.xcodeproj -scheme Neochi -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO -quiet build
APP=$(find build/Build/Products -name 'Neochi.app' -maxdepth 3 | head -1)
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" "$BID"
