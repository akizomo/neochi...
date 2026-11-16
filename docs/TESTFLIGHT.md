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
| 読み込めないとき | Release では見本の番組を出さず、「番組を読み込めませんでした」と「もう一度」を出す(DEBUG と接続先なしは見本で動く) |
| App Store Connect のアプリ | 作成済み(2026-11-15) |
| ターミナルでの書き出し | `ios/Scripts/release-testflight.sh` で、IPA の書き出しまで通る(2026-11-15 確認)。配布用の署名(Apple Distribution)、HealthKit のエンタイトルメント、バージョン、アイコン、プライバシーマニフェストが入っていることを確かめた。**実機の登録は要らない** |

## あなたの作業(私にはできない)

1. Bundle ID は `com.example.neochi` のまま使う(2026-11-16 に決めた。アップロード済みで、変えると別アプリになり、テスターの再招待が要るため)。
2. Apple Developer Program に登録済みか確認する。App ID(HealthKit を有効)を作る(SETUP.md A-3)。
3. App Store Connect でアプリを作る(名前 NeochiPickzz。使用済みと言われたら教える)。
4. **Supabase の「Allow anonymous sign-ins」をオンにする**(Authentication → Providers)。いまはオフ(登録の応答が 422)。オフのままだと、朝の振り返りの記録がサーバーに送れない。
5. プライバシーポリシーを公開して、URL を App Store Connect の App Privacy に入れる(SETUP.md E の下書き)。App Privacy の回答は、`PrivacyInfo.xcprivacy` と同じ内容(睡眠データ・デバイスID、ユーザーに紐づく、追跡なし、アプリの機能)。
6. 正式なロゴ(1024×1024、角丸なし)を渡す。`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` を差し替える。
7. Xcode で Apple ID を登録する(Settings → Accounts)。

## ターミナルだけで出す(登録済みの実機なしで可。Bitdone リポジトリの手法)

```bash
ios/Scripts/release-testflight.sh            # IPA を書き出すまで(アップロードしない)
ios/Scripts/release-testflight.sh --upload   # App Store Connect にアップロードする
```

- 署名なしでアーカイブ → 開発用の証明書で仮署名して HealthKit のエンタイトルメントを埋め込む → 書き出しのときに配布用の署名を付ける、の3段。`-allowProvisioningUpdates` で署名つきのアーカイブをすると、開発用プロファイルを作ろうとして `Your team has no devices` で落ちるため、署名を書き出しに回している。
- Xcode にログイン済みの Apple ID を使う(API キーは不要)。チーム ID と証明書は、この Mac から読む(リポジトリには書かない)。
- 書き出しが `The request expected results but none were found` で落ちたら、Apple 側の一時的なエラー。少し待って、同じコマンドをもう一度。
- ビルド番号は、アップロードのたびに上げる(`ios/project.yml` の `CURRENT_PROJECT_VERSION`)。

## 実機を登録する(Xcode の画面から出す場合だけ。ターミナルで出すなら不要)

1. iPhone を USB で Mac につなぎ、「このコンピュータを信頼」を押す。iPhone の設定 → プライバシーとセキュリティ → デベロッパモードをオンにして、再起動する。
2. Xcode → Window → Devices and Simulators に、iPhone が出ることを確かめる。
3. Neochi ターゲット → Signing & Capabilities で Team を選ぶと、Xcode がデバイスを登録し、プロファイルを作る。(つなげない場合は、developer.apple.com → Devices に、iPhone の UDID を手で足す)

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
