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

## これから

トークンの Swift 化 → SwiftUI の画面 → 再生(AVPlayer) → HealthKit → Supabase。
