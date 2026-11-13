# neochi… iOS アプリ

SwiftUI の iOS アプリ(MVP)。画面・色・部品の規則は、デザインシステムと `docs`(別途)に従う。

## 構成

- `Sources/NeochiCore/`: アプリの判断ロジック。Apple のフレームワークに依存しない。
  - `TonightEngine`: 今夜の3つ(安心→変化→冒険)と、回の決め方。昨夜30分未満で寝落ちできた回は、3回目まで同じ回。3回に達した回は外れる。
  - `Reason`: なぜその候補か(あなたの実績に基づく理由)。
  - `BedtimeWindow`: 就寝の時間帯。この時間帯にアプリを開いたら、夜の画面を出す。
  - `Models`, `Strings`: モデルと、表示文字列(絵文字なし)。
- `../design/tokens.json`: デザイントークンの唯一の出どころ。

## テスト(Mac でも Linux でも通る)

```bash
cd ios && swift test
```

## 状況

できていること: デザイントークンの Swift 化、SwiftUI の画面一式、再生(AVPlayer)とスリープタイマー、HealthKit の入眠読み取り、朝の振り返りと記録の端末内保存、Supabase の読み込み(番組・回・観点ごとの★)と記録の送信。

- 見本データ(`App/Model/SampleData.swift`)で起動し、Supabase が設定済みで読めたときだけ実データに差し替える。未設定・失敗時は見本のまま動く。
- 差し替え時は、実データに無い番組を指す履歴・お気に入り・予約・昨夜の記録を `SessionState.reconciled` で外す。

## これから

- 解析パイプラインを実データで回し、Supabase に回と解析結果を入れる(ルートの README 参照)。
- 実機(TestFlight)で、再生・ヘルスケアの許可・記録の送信を確かめる(`../docs/SETUP.md`)。
- 見本の履歴を、端末内の記録(`LogStore`)から作る履歴に置き換える。
