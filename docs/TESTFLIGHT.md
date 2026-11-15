# TestFlight に出す手順(2026-11-15 時点)

セットアップの全体は `docs/SETUP.md`(A: Apple Developer から TestFlight まで)。この文書は、そのうち「いま何が済んで、何が残っているか」と、アップロードの具体的な手順。トラックは、ローカルの Xcode でビルドする(Expo/EAS ではない)。

## 状態

| 項目 | 状態 |
|---|---|
| Release のデバイス向けビルド(署名なし) | 通る(Xcode 27.2、iOS 17.0 以上、iPhone のみ) |
| ホーム画面の名前 | NeochiPickzz(`project.yml` の `INFOPLIST_KEY_CFBundleDisplayName`。xcodegen は Info.plist を作り直すので、ここに置く) |
| アプリアイコン | **仮**(`App/Assets.xcassets`。N の3本線の簡易版)。正式なロゴに差し替える |
| プライバシーマニフェスト | `App/PrivacyInfo.xcprivacy`(UserDefaults の理由 CA92.1、収集: 睡眠データ・デバイスID、追跡なし) |
| HealthKit | 権限と読み取りの説明文あり(読み取りのみ) |
| バックグラウンド再生 | `UIBackgroundModes: audio` あり。**実機では未確認** |
| 暗号化の質問 | `ITSAppUsesNonExemptEncryption: NO` で聞かれない |
| バージョン | 0.1.0(ビルド 1)。**アップロードのたびにビルド番号を上げる** |

## あなたの作業(私にはできない)

1. **Bundle ID を決める**(`com.<名前>.neochi` の形)。いまは `com.example.neochi` の仮。決まったら `ios/project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` と `bundleIdPrefix` を直す(私がやる)。
2. Apple Developer Program に登録済みか確認する。App ID(HealthKit を有効)を作る(SETUP.md A-3)。
3. App Store Connect でアプリを作る(名前 NeochiPickzz。使用済みと言われたら教える)。
4. **Supabase の「Allow anonymous sign-ins」をオンにする**(Authentication → Providers)。いまはオフ(登録の応答が 422)。オフのままだと、朝の振り返りの記録がサーバーに送れない。
5. プライバシーポリシーを公開して、URL を App Store Connect の App Privacy に入れる(SETUP.md E の下書き)。App Privacy の回答は、`PrivacyInfo.xcprivacy` と同じ内容(睡眠データ・デバイスID、ユーザーに紐づく、追跡なし、アプリの機能)。
6. 正式なロゴ(1024×1024、角丸なし)を渡す。`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` を差し替える。
7. Xcode で Apple ID を登録する(Settings → Accounts)。

## アップロード

1. `cd ios && xcodegen generate && open Neochi.xcodeproj`
2. Neochi ターゲット → Signing & Capabilities → Team を選ぶ(Automatically manage signing)。HealthKit と Background Modes(Audio)が並んでいることを確かめる。
3. 実機(Any iOS Device)を選び、Product → Archive → Organizer → Distribute App → App Store Connect → Upload。
   - 登録済みの実機が0台だと、CLI の `xcodebuild archive -allowProvisioningUpdates` は失敗する。Organizer から出す。
4. App Store Connect → TestFlight にビルドが出るまで待つ(数十分)。内部テストのグループに、自分を足す。
5. iPhone の TestFlight から入れて、下の「実機で確かめること」を行う。

## 実機で確かめること(初回の最優先)

1. 「いま聴く」で、音が出るまでの時間(25秒で失敗の表示になる)。
2. 画面をロックしても、鳴り続けるか。ロック画面に番組名と再生/一時停止だけが出るか。
3. 再生中に着信や別アプリの音声で中断され、終わったあとに戻るか。
4. 機内モードで「再生できませんでした」と「もう一度」が出るか。
5. ヘルスケアの許可画面が出て、睡眠の読み取りを許可できるか。Apple Watch を着けて寝た翌朝、入眠の時刻が取れるか。
6. 朝の振り返りで記録して、Supabase の `sleep_log` に行が入るか(匿名ログインをオンにしたあと)。
7. 通信が失敗したときに、サンプルの番組(電話帳を読む会など)が出てしまわないか(下の既知の課題)。

## 既知の課題(出す前に決める)

- **読み込みに失敗すると、サンプルの番組が出る**(`AppModel.sample()` のまま)。テスターが、本物の番組と取り違える。Release では、サンプルを出さず、「読み込めませんでした」と再読み込みを出すのが安全。
- **外部テスト(公開リンク)には、Beta App Review がある。** 他者の著作物である番組の音声を、アプリで再生する点が、審査で聞かれる可能性がある。内部テスト(自分と、App Store Connect のユーザー)は、審査なしで始められる。まず内部で。
- Xcode が正式版か確認する(ベータ/RC のビルドは、App Store Connect に弾かれることがある)。
- 解析結果の再測定(`python -m neochi remeasure`)は、本番キーのある環境で別に行う。
