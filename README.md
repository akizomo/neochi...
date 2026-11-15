# NeochiPickzz 解析パイプライン

ポッドキャストの回を解析し、🎯🌊🎧 と総合評点を保存する Python バッチ。

```bash
pip install -e '.[asr,llm,dev]'
cp .env.example .env          # ANTHROPIC_API_KEY(+ Supabase を使うなら URL と service key)
python -m pytest              # 外部通信なしで通る
python -m neochi run --limit 100 --max-new 12   # 🎧まで計算し、🌊🎯は work/pending/ に書き出す(APIなし)
#  → Claude のセッションが work/pending/*.json を読み、config/rubric.md に沿って work/judgements.jsonl を書く
python -m neochi apply                          # 判定を取り込んで★を確定、data/store.json に保存
python -m neochi run --judge api                # API で判定する場合(ANTHROPIC_API_KEY が必要)
python -m neochi z-rank       # sleep_log の実測(watch)から 総合評点と寝落ち格付けを更新
```

- 🌊🎯の判定は既定で Claude のセッション(スケジュール実行)が行う。API は、サイトやアプリからその場で判定が要るときだけ使う
- 保存先: `SUPABASE_URL` / `SUPABASE_SERVICE_KEY` があれば Supabase、なければ `data/store.json`(リポジトリにコミットして次回に引き継ぐ。文字起こしは入れない)。スキーマは `supabase/migrations/0001_init.sql`
- ルールは `config/`(`scoring.yaml` = 🎧・総合・総合評点、`z_rank.yaml` = 寝落ち格付け Z/ZZ/ZZZ、`rubric.md` = LLM 採点基準)。数値はすべて仮
- 表示文字列は `neochi/strings.py` だけ。`tests/test_strings.py` が禁止語・🥄 を検査
- `input_depth`: `meta` = メタ情報のみ / `audio` = 音響特徴量まで / `transcript` = 文字起こし+LLM 判定まで
- 音声は一時ディレクトリに落とし、`with` を抜けたら消える(保存・配信しない)
- 総合評点は `scoring.final_star` の機械的な算出のみ。実測3件・みんな10件に達するまでは AI解析のみ。手で上書きしない。格付けは番組の評点だけで決め、基準未満は掲載しない(docs/SCORE.md)
