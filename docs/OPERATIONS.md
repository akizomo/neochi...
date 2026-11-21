# 解析の運用指示書（スケジュールタスク）

新着回の解析と採点を、Claude のスケジュールタスクで回すための手順。採点基準は `config/rubric.md`、スコアの定義は `docs/SCORE.md`。

## 1. 最初に一度だけやること

| # | 作業 | 場所 | 確認 |
| --- | --- | --- | --- |
| 1 | `supabase/migrations/0005_interest_score.sql` を実行 | Supabase の SQL Editor | `analysis` に `interest_score` 列がある |
| 1b | `supabase/migrations/0007_detail_viz.sql` を実行(2026-11-15 実行済み) | Supabase の SQL Editor | `analysis` に `calm_per_min`・`content_summary` 列、view `show_sleep_points` がある |
| 1c | `supabase/migrations/0008_show_cohort.sql` を実行し、続けて `python -m neochi sync-shows` を1回流す(2026-11-15 追加。**次の解析より前に**。未実行だと解析が `cohort` 列で失敗する) | Supabase の SQL Editor と、手元のターミナル(service key を入れて) | `show` に `cohort` 列があり、`cohort`・`apple_category` 列があり、`genre` が 寝落ち用・朗読・環境音・コメディ・雑談・教養 だけ |
| 1d | `supabase/migrations/0012_transcript.sql` を実行(2026-11-19 追加。文字起こしを保存する非公開の表)。未実行でも解析は動くが、文字起こしが保存されず、警告が出る | Supabase の SQL Editor | `transcript` 表がある。解析のログに「文字起こしを保存できませんでした」が出ない |
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
4. 判定を work/judgements.jsonl に1行1件で書く。rubric.md の出力形式（hook・follow・imagery の観察、calm A〜D、calm_per_min、moments、content_summary、content_start、reason）に episode_id を加えたJSON。★や合計は書かない。
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

### 採点ルールや格付けの線を変えたあと(本番に反映する)

1. 環境変数 `SUPABASE_URL` と `SUPABASE_SERVICE_KEY` を入れる(値は表示しない。`set -a; source .env.local; set +a`)。
2. 先にドライラン。何も保存せず、格付けの割合(変更前 → 変更後)と、変わる番組の件数だけが出る。
   `python -m neochi z-rank --rules-changed --dry-run`
3. 割合が方針(ZZZ 約15%、ZZ 約30%、Z 約35%、載せない 約2割。`docs/SCORE.md` §3c)から大きく外れていたら、本番に書かずに、線を直す。
4. 反映する。🌊(項目の点から)と🎧(特徴から)も計算し直し、格付けを付け直す。
   `python -m neochi z-rank --rules-changed`
5. サイトは毎朝つくり直される(`.github/workflows/site.yml`)。すぐ見るときは Vercel で再デプロイする。

戻すときは、設定を元に戻して、4 をもう一度流す(評点の元は保存済みの項目と特徴なので、計算し直せる)。項目の点を持たない古い解析は、🌊の幅が旧式のまま。

## 7. 定義を変えたとき、どこからやり直すか

解析は、①音声の取得 → ②文字起こし → ③LLM の判定 → ④点の計算、の4段階。②の結果(`transcript` 表、非公開)と、各行を作った定義の版(`analysis.reasons.versions` の `transcript` / `rubric` / `scoring`)を保存している。版は中身のハッシュなので、定義を直せば自動で変わる。

| 変えたもの | やり直す段階 | 命令 |
|---|---|---|
| 重み、線、点への換算(`config/scoring.yaml`、`z_rank.yaml`) | ④だけ | `python -m neochi z-rank --rules-changed` |
| 採点基準(`config/rubric.md`) | ③と④(音声・文字起こしは使わない) | `python -m neochi repending --stale` → セッションが `work/pending` を判定 → `python -m neochi apply` |
| 🎧の音響の測り方 | 音響だけ | `python -m neochi remeasure` |
| 文字起こしのやり方(モデル・範囲) | ①②③④すべて | `python -m neochi run --force` |

- `repending` は、保存した文字起こしから判定待ちを作り直す。`--stale` は、古い基準(版が違う、または記録がない)で判定した回だけ。`--episodes ID,ID` で回を指定、`--limit N` で件数を絞る。確かめ用の少数の回で判定が安定するのを確かめてから、全体に広げる。
- 版の記録がない回(2026-11-19 より前に解析した回)と、文字起こしが保存されていない回は、`run --force` で取り直すまで、`repending` の対象にならない(件数が最後に出る)。

## 文字起こしの保存について(2026-11-21)

- 新しい回で、文字起こしが保存されない不具合があった(2026-11-19 〜 11-21)。`transcript` 表は `episode` を参照するのに、回の登録より前に保存していたので、初めて解析する回は、参照先がなく失敗し、警告だけ出て続行していた。回の登録のあとに保存するよう直した(テストあり)。
- 過去の回の取り直しは `python -m neochi retranscribe --all --shard i/n`(保存済みはスキップ。並列に回せる)。
- 毎週の解析のあとに、新しい回に `transcript` の行があるかを確かめる(なければ、保存の警告が出ている)。
- 音声そのものは保存しない(元の配信から、いつでも取り直せる。保存するのは、文字起こしと特徴量)。
