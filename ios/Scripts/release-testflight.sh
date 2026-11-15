#!/usr/bin/env bash
# TestFlight に出すための、ターミナルだけのアーカイブ → 書き出し(→ アップロード)。
# 手法は Bitdone リポジトリの docs/IOS_RELEASE.md §2' から。登録済みの実機が0台でも通る。
#   - 署名なしでアーカイブする(-allowProvisioningUpdates で署名すると、開発用プロファイルを作ろうとして「Your team has no devices」で落ちる)
#   - 開発用の証明書で仮署名して、エンタイトルメント(HealthKit)を埋め込む(署名なしだと、書き出したアプリから抜ける)
#   - 配布用の署名は、書き出し(export)のときに付く(Xcode にログイン済みの Apple ID を使う。API キーは不要)
#
# 使い方:
#   ios/Scripts/release-testflight.sh            # IPA を書き出すまで(アップロードしない)
#   ios/Scripts/release-testflight.sh --upload   # App Store Connect にアップロードする(Apple に送る操作なので、必ず確認してから)
# ビルド番号は、アップロードのたびに前より大きくする(ios/project.yml の CURRENT_PROJECT_VERSION)。
set -euo pipefail

UPLOAD=0; [ "${1:-}" = "--upload" ] && UPLOAD=1
cd "$(dirname "$0")/.."                         # ios/
OUT="${RELEASE_OUT:-${TMPDIR:-/tmp}/neochi-release}"
ARCHIVE="$OUT/Neochi.xcarchive"
rm -rf "$OUT"; mkdir -p "$OUT"

# 開発用の証明書と、チーム ID(証明書の OU)を、この Mac から読む。リポジトリには書かない。
ID=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
[ -n "$ID" ] || { echo "Apple Development の証明書が見つかりません。Xcode の Settings → Accounts でログインしてください" >&2; exit 1; }
TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -E 's/.*OU=([A-Z0-9]+).*/\1/')
BUNDLE=$(xcodebuild -project Neochi.xcodeproj -scheme Neochi -showBuildSettings 2>/dev/null | awk '/ PRODUCT_BUNDLE_IDENTIFIER =/{print $3}')
echo "bundle=$BUNDLE team=$TEAM"

xcodegen generate >/dev/null

echo "1/3 署名なしでアーカイブ"
xcodebuild archive -project Neochi.xcodeproj -scheme Neochi -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" CODE_SIGNING_ALLOWED=NO | tail -3

echo "2/3 開発用の証明書で仮署名して、エンタイトルメントを埋め込む"
APP="$ARCHIVE/Products/Applications/Neochi.app"
cp App/Neochi.entitlements "$OUT/app.entitlements"
/usr/libexec/PlistBuddy -c "Add :application-identifier string $TEAM.$BUNDLE" \
  -c "Add :com.apple.developer.team-identifier string $TEAM" "$OUT/app.entitlements"
if [ -d "$APP/Frameworks" ]; then
  for f in "$APP"/Frameworks/*.framework; do codesign -f -s "$ID" --timestamp=none "$f"; done
fi
codesign -f -s "$ID" --timestamp=none --entitlements "$OUT/app.entitlements" "$APP"

# 書き出しの設定。チーム ID は、この Mac から読んだものを、実行時に入れる
DEST=export; [ "$UPLOAD" = 1 ] && DEST=upload
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$DEST</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM</string>
<key>uploadSymbols</key><true/>
</dict></plist>
PLIST

echo "3/3 配布用の署名で書き出し($DEST)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates | tail -5
echo "完了: $OUT/export"
ls "$OUT/export" 2>/dev/null || true
