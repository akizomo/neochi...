# セットアップ手順(あなたが行う作業)

この手順書は記憶に基づく。公式ドキュメントのうち、supabase.com は取得できず、Apple は一部しか確かめていない。画面の名前や並びが違っていたら、近い項目を選んで進め、違いを教えてほしい。

先に行うこと(優先順):
1. Apple Developer Program への登録(承認に日数がかかることがあるので最初に出す)
2. Supabase のプロジェクト作成と、SQL の実行
3. Mac と Xcode の用意

秘密の値(キー、パスワード)は、チャットに貼らない。この手順書の「値を控える」は、自分のパスワード管理ツールに控える、という意味。

---

## A. Apple Developer Program から TestFlight まで

1. 登録する。
   - Apple ID(二要素認証つき)で、Apple Developer Program に個人として登録する。年額の有料プラン。金額と支払い方法は、登録画面で確認する。
   - 確認: 登録画面で「購入済み」「承認待ち」などの状態が出る。承認されると、developer.apple.com の Account に Certificates, Identifiers & Profiles が出る。
2. Bundle ID を決める。**ここはあなたが決める。**
   - 形は `com.<あなたの名前や屋号>.neochi`(逆ドメイン形式)。一度アプリを作ると変えにくいので、先に決めて、私にも教える。
   - 確認: 決めた文字列を、メモに書いた。
3. App ID を作る。
   - Account → Certificates, Identifiers & Profiles → Identifiers → + → App IDs → App。Description は「neochi」、Bundle ID は Explicit で、2 の文字列。
   - Capabilities の一覧から、**HealthKit** にチェックを入れて Register。
   - 確認: Identifiers の一覧に、Bundle ID が出て、HealthKit が有効と表示される。
4. Background Modes(Audio)は、Xcode で付ける(ポータルの一覧にはない)。
   - Xcode でプロジェクトを開き、Signing & Capabilities → + Capability → Background Modes → **Audio, AirPlay, and Picture in Picture** にチェック。HealthKit の Capability も、同じ画面で追加する。
   - 確認: Signing & Capabilities に、HealthKit と Background Modes の2つが並ぶ。
5. App Store Connect でアプリを作る。
   - appstoreconnect.apple.com → Apps → + → New App。プラットフォームは iOS、言語は日本語、名前は「neochi」(「neochi…」の三点リーダーが使えなければ、記号なしで)、Bundle ID は 2 のもの、SKU は任意の英数字(例: neochi-001)。
   - 確認: Apps の一覧にアプリが出る。名前が使用済みと言われたら、そこで重複に気づける(F も参照)。
6. ビルドをアップロードする(Xcode のビルドができてから)。
   - Xcode で、実機ではなく Any iOS Device を選び、Product → Archive → Distribute App → App Store Connect → Upload。
   - 確認: App Store Connect の TestFlight タブに、ビルドが出る(処理に数十分かかることがある)。
7. 暗号化の質問に答える。
   - ビルドごとに、暗号化の利用について聞かれる。標準の HTTPS 通信だけなら、免除の扱い。`Info.plist` の `ITSAppUsesNonExemptEncryption` を `NO` にしておくと、毎回聞かれない。
   - 確認: ビルドの状態が「テストの準備完了」などになる。
8. 内部テストを始める。
   - TestFlight → 内部テスト → グループを作る → 自分(App Store Connect のユーザー)を追加 → ビルドを選ぶ。内部テストは、アプリのレビューなしで始められる。
   - iPhone に TestFlight アプリを入れ、招待から neochi を入れる。
   - 確認: iPhone に neochi が入り、起動できる。
9. ヘルスケアの許可を確かめる(アプリができてから)。
   - 初回起動時に、ヘルスケアの許可画面が出る。睡眠の読み取りを許可する。Apple Watch を着けて眠ると、睡眠データがヘルスケアに入る。
   - 確認: ヘルスケアアプリの「睡眠」に、前の晩のデータが出る。

## B. Mac と Xcode

1. Mac を用意する。最新の Xcode が動く macOS が必要。Mac がない場合は、先に教えてほしい(クラウドでのビルドなど、別の道を考える)。実機での動作確認には、iPhone も必要。
   - 確認: Mac の「このMacについて」で、macOS のバージョンを控えた。
2. Xcode を入れる。Mac App Store から、Xcode の最新の安定版を入れ、一度起動して、追加コンポーネントの入れ込みを済ませる。
   - 確認: Xcode のメニュー Xcode → About Xcode でバージョンが出る。
3. Apple ID を Xcode に登録する。Xcode → Settings → Accounts → + → Apple ID。登録した Developer Program のチームが表示される。
   - 確認: Accounts に、チーム名と、種別「Individual」(または同等)が出る。
4. リポジトリを取得する。
   ```bash
   git clone https://github.com/akizomo/neochi...
   cd neochi.../ios
   swift test
   ```
   - 確認: テストが全件通る(`Executed 19 tests, with 0 failures` のような表示)。
5. Xcode のプロジェクトを生成する(`ios/project.yml` ができたら)。XcodeGen を使う予定。
   ```bash
   brew install xcodegen
   cd ios && xcodegen generate
   ```
   - 確認: `ios/` に `Neochi.xcodeproj` ができ、Xcode で開ける。

## C. Supabase

1. プロジェクトを作る。
   - supabase.com にログイン → New project。名前は `neochi`、リージョンは Northeast Asia (Tokyo)、データベースのパスワードを決める。パスワードは控える。
   - 確認: ダッシュボードが開き、プロジェクトの状態が準備完了になる(数分かかる)。
2. 匿名ログインを有効にする。
   - Authentication → Sign In / Providers(または Providers)→ **Allow anonymous sign-ins** をオンにして保存。ログインなしで、端末ごとの記録を分けるため。
   - 確認: 設定を保存し直してもオンのまま。
3. テーブルを作る。SQL エディタ(左のメニューの SQL Editor)で、New query を開き、リポジトリの次のファイルの中身を、**この順に**貼って Run する。
   1. `supabase/migrations/0001_init.sql`
   2. `supabase/migrations/0002_artwork.sql`
   3. `supabase/migrations/0003_rls.sql`
   - 確認: Table Editor に show、episode、analysis、sleep_log、play_record の5つが出る。Authentication → Policies(または各テーブルの RLS の表示)に、ポリシーが並び、sleep_log と play_record は「自分の行だけ」になっている。
4. URL とキーを控える。
   - Project Settings → API(または API Keys)。次の3つを、パスワード管理ツールに控える。
     - Project URL
     - anon キー(アプリ用。新しい画面では「Publishable key」と呼ばれることがある)
     - service_role キー(解析バッチ専用。新しい画面では「Secret key」と呼ばれることがある)
   - **キーをチャットに貼らない。service_role キーは、アプリにも、git にも入れない。** アプリに入れるのは、Project URL と anon キーだけ。
   - 確認: 3つを控えた。service_role キーを、どこにも貼っていない。
5. (あとで)匿名ログインの悪用対策。公開前に、レート制限や CAPTCHA の有効化を検討する。

## D. GitHub の Secrets(解析バッチ用)

1. リポジトリの Settings → Secrets and variables → Actions → New repository secret で、次の3つを登録する。値は、貼り付けるだけで、チャットには出さない。
   - `SUPABASE_URL`: C-4 の Project URL
   - `SUPABASE_SERVICE_KEY`: C-4 の service_role キー(Secret key)
   - `ANTHROPIC_API_KEY`: console.anthropic.com → API Keys で作成。利用には、クレジットの登録が要る。
   - 確認: Secrets の一覧に、3つの名前が出る(値は表示されない)。
2. リポジトリ名を変える場合(`neochi...` から、ドットなしの名前へ)は、変えたあとも Secrets が残っていることを確かめる。
   - 確認: 名前を変えたあとの Secrets の一覧に、3つが残っている。

## E. プライバシーポリシー

App Store の審査と、ヘルスケアのデータを扱うアプリに必要。公開した URL を、App Store Connect の App Privacy と、アプリの情報に入れる。

下書き(`[ ]` は、あなたが埋める):

> **neochi… プライバシーポリシー**
>
> [事業者名・個人名]( 以下「運営者」)は、neochi…(以下「本アプリ」)で扱う情報について、次のとおり定めます。
>
> **取得する情報**
> 1. ヘルスケアの睡眠データ(読み取りのみ。端末の許可を得た場合に限ります)
> 2. 再生した番組と回、再生の開始と終了の時刻
> 3. 利用者が入力する評価(程よい興味、起伏の少なさ)とメモ
> 4. アプリが自動で付ける匿名の識別子(氏名、メールアドレスなどは取得しません)
>
> **利用目的**
> ヘルスケアの睡眠データは、再生を始めてから寝落ちするまでの時間を推定し、番組ごとの結果を記録するためだけに使います。広告には使いません。第三者に提供しません。その他の情報は、本アプリの機能の提供と、番組の紹介と、解析の見直しのために使います。
>
> **保存と管理**
> 情報は、運営者が契約するクラウドのデータベース(日本のリージョン)に保存します。端末ごとの記録は、その端末の識別子でのみ読み書きできます。
>
> **削除**
> アプリ内の設定から、記録を削除できます。[ほかの削除の依頼は、下記の連絡先へ。]
>
> **本アプリの位置づけ**
> 本アプリは、ポッドキャスト番組を紹介し、利用者が測った記録を示すものです。医療機器ではなく、健康状態を判断するものではありません。
>
> **変更**
> 内容を変えるときは、このページで知らせます。
>
> **連絡先**
> [メールアドレスなど]
>
> 制定日: [年月日]

- 避ける言葉: 診断に見える語(不眠、障害、病気、症状)、効能の約束(改善、治る、効果、効く)、睡眠の質。上の下書きにも入れていない。直すときも、入れない。
- 公開場所の案(上から、手間が少ない順):
  1. GitHub Pages: リポジトリの `docs/` を公開する。無料で、手順が少ない。リポジトリ名を変えると URL も変わる。
  2. Notion の公開ページ: すぐ作れる。URL の変更に弱い。
  3. 自分のドメインの静的ページ(Vercel など): 名前の重複確認(F)でドメインが取れたら。
  - 確認: 公開した URL を、ログインなしのブラウザで開いて、全文が読める。

## F. 名前の重複確認(neochi…)

1. App Store: App Store Connect でのアプリ作成時に、名前が使えるか分かる。事前に、App Store で「neochi」を検索する。
   - 確認: 同じ名前の、別のアプリがない。
2. ドメイン: 取りたい名前(例: neochi.app、neochi.jp)を、レジストラの検索で調べる。
   - 確認: 取れる、または取れない理由が分かった。
3. X のハンドル: x.com で `@neochi` などを検索し、取得できるか確かめる。
   - 確認: 使えるハンドルを、1つ決めた。
4. 商標: J-PlatPat(特許情報プラットフォーム)の商標検索で、「neochi」と「ネオチ」を検索する。区分は、アプリ(9類)を中心に、近い区分(41類、42類など)も見る。
   - 確認: 同一や似た商標が、ないことを確かめた。あれば、結果を私に教えてほしい。
