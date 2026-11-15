# 解析の運用指示書（スケジュールタスク）

新着回の解析と採点を、Claude のスケジュールタスクで回すための手順。採点基準は `config/rubric.md`、スコアの定義は `docs/SCORE.md`。

## 1. 最初に一度だけやること

| # | 作業 | 場所 | 確認 |
| --- | --- | --- | --- |
| 1 | `supabase/migrations/0005_interest_score.sql` を実行 | Supabase の SQL Editor | `analysis` に `interest_score` 列がある |
| 2 | 環境変数 `SUPABASE_URL` と `SUPABASE_SERVICE_KEY` を入れる | claude.ai/code → 環境の設定（歯車） | 名前は大文字小文字まで一致。引用符・`export`・前後の空白なし |
| 3 | 手順2で変数を入れた**同じ環境**を選んでタスクを作る | claude.ai/code → スケジュールタスク → 新規 | タスクの詳細に環境名が出る |
| 4 | 「今すぐ実行」で1回動かす | 同上 | 報告の「保存先」が Supabase |

- `SUPABASE_SERVICE_KEY` は service_role（secret）。publishable（anon）では書き込めない。キーはチャットに貼らない・コミットしない。
- 変数は環境ごとに別。タスクを作った環境と、変数を入れた環境が違うと「未設定」になる。

## 2. タスクの設定

| 項目 | 指定 |
| --- | --- |
| 環境 | 手順1-2で変数を入れた環境 |
| モデル | Sonnet 5.5 |
| 頻度 | 週1回の自動 + 必要なとき手動 |
| 担当 | 最初は全体を1本。上限に当たらないと分かってから3分割 |
| 1回の件数 | `--max-new 6` |

3分割するときは、コマンドの `--shard` だけ変え（`0/3` `1/3` `2/3`）、同じ環境で3つ作る。3つ同時に動かしても合計の使用量は減らない。

## 3. タスクに貼るプロンプト

```
寝落ちスコア（Neochi）の新着エピソードを解析して採点してください。Claude APIは使わず、🌊🎯の判定はこのセッションのあなたが行います。

## 手順
0. 環境変数 SUPABASE_URL と SUPABASE_SERVICE_KEY が両方あるかを、値を表示せずに確認する。どちらかがなければ「Supabase が未設定のため実行しなかった」と、現在見えている環境変数の「名前だけ」（値は出さない。名前に SUPA を含むもの）を添えて報告し、解析せずに終える。
1. GitHub の akizomo/neochi... をクローンし（main）、`pip install -e '.[asr,dev]' --break-system-packages` で準備する。`python -m pytest -q` が通ることを確認する。
2. `python -m neochi run --limit 100 --max-new 6 --judge session` を実行する。解析済みの回は自動でスキップされる。時間がかかるので、タイムアウトは長めにする。
3. config/rubric.md を最初に読み、その基準どおりに work/pending/*.json を1件ずつ判定する。ジャンルや番組名では判断せず、聞いた内容の観察項目だけで採点する。冒頭の広告やお知らせは採点に含めない。
4. 判定を work/judgements.jsonl に1行1件で書く。rubric.md の出力形式（interest A〜E、calm A〜D、moments、reason）に episode_id を加えたJSON。★や合計は書かない。
5. `python -m neochi apply` で取り込む。コミットはしない。
6. 最後に、今回採点した回を表で報告する（番組 / 回 / 🎯点数(1〜10) / 🌊★ / 🎧★ / 最終★ / 根拠 / 保存先）。保存先が Supabase か data/store.json かを必ず書く。

## 守ること
- 音声ファイルは解析後に必ず消す
- ★を手で動かさない。変えるのは判定だけ
- 環境変数の値（キー）は、出力・ログ・コミットのどこにも出さない
- 新着がなければ「新着なし」と報告して終える
```

## 4. 100番組を一通り終えるまで

手動で「今すぐ実行」を繰り返す（目安5〜6回）。解析済みの回は自動で飛ばされるので重複しない。

## 5. うまくいかないとき

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| 「Supabase が未設定」 | 変数を入れた環境と、タスクの環境が違う／名前の打ち間違い | 報告に出る「SUPA を含む変数の名前」を確認。環境を揃える |
| 失敗理由が USAGE_LIMIT_REACHED | プランの利用上限（タスクの不具合ではない） | 時間を空けて再実行。分割は1本ずつ時間をずらす |
| `interest_score` が保存されない | 0005 が未実行 | SQL Editor で0005を実行 |
| 保存先が data/store.json | 変数が見えていない | 上と同じ。Supabase には入っていない |

## 6. 基準を変えるとき

採点基準は `config/rubric.md` だけを直す（プロンプトは「rubric.md を読んで採点」なので変更不要）。スコアの式やゾーンは `config/scoring.yaml`、定義の説明は `docs/SCORE.md`。変更後は `python -m pytest -q` を通す。
