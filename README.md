# neochi… 解析パイプライン

ポッドキャストの回を解析し、🎯🌊🎧 と最終★を保存する Python バッチ。

```bash
pip install -e '.[asr,llm,dev]'
cp .env.example .env          # ANTHROPIC_API_KEY(+ Supabase を使うなら URL と service key)
python -m pytest              # 外部通信なしで通る
python -m neochi run --csv data/shows.csv --limit 10
python -m neochi z-rank       # sleep_log の実測(watch)から Z ランクを更新
```

- 保存先: `SUPABASE_URL` / `SUPABASE_SERVICE_KEY` があれば Supabase、なければ `out/store.json`。スキーマは `supabase/migrations/0001_init.sql`
- ルールは `config/`(`scoring.yaml` = 🎧・総合・最終★、`z_rank.yaml` = Z/ZZ/ZZZ、`rubric.md` = LLM 採点基準)。数値はすべて仮
- 表示文字列は `neochi/strings.py` だけ。`tests/test_strings.py` が禁止語・🥄 を検査
- `input_depth`: `meta` = メタ情報のみ / `audio` = 音響特徴量まで / `transcript` = 文字起こし+LLM 判定まで
- 音声は一時ディレクトリに落とし、`with` を抜けたら消える(保存・配信しない)
- 最終★は `scoring.final_star` の機械的な算出のみ。みんなが0件の間は AI解析のみ。手で上書きしない
