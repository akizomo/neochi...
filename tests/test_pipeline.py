import contextlib
import json
import logging
import os
import tempfile

import numpy as np

from neochi import feeds, pipeline
from neochi.store import JsonStore

SHOW = feeds.Show(id=feeds.show_id("https://x/f"), title="テスト番組", publisher="p", rss_url="https://x/f", genre="雑談")


def ep(i):
    return feeds.Episode(id=feeds.episode_id(SHOW.id, str(i)), show_id=SHOW.id, title=f"第{i}回",
                         audio_url="https://x/a.mp3", duration_sec=600, published_at=None)


def make_deps(loud=False, made_dirs=None):
    @contextlib.contextmanager
    def download(url):
        with tempfile.TemporaryDirectory() as d:
            made_dirs.append(d)
            yield os.path.join(d, "a")

    def decode(path, sr=8000, **_):
        x = np.random.default_rng(1).normal(0, 0.01, sr * 120).astype(np.float32)
        if loud:  # 毎秒大きな音 → 異常値
            x = (x.reshape(-1, sr) * np.tile([1, 50], 60)[:, None]).reshape(-1)
        return x

    return pipeline.Deps(
        download=download, decode=decode,
        transcribe=lambda path, dur, lang, cfg: ("あ" * 500, 2.0),
        judge=lambda *a, **k: {"calm_star": 4.5, "interest_level": "mid", "reason": "淡々としています"},
    )


def test_rerun_is_idempotent_and_audio_removed(cfg, tmp_path):
    store, dirs = JsonStore(tmp_path / "s.json"), []
    for _ in range(2):
        for i in range(3):
            row = pipeline.analyze_episode(SHOW, ep(i), cfg, store, make_deps(made_dirs=dirs))
    assert len(store.rows("analysis")) == 3
    assert row["input_depth"] == "transcript" and row["final_star"] is not None
    assert dirs and not any(os.path.exists(d) for d in dirs)  # 音声は残っていない


def test_remeasure_changes_only_acoustics(cfg, tmp_path):
    store = JsonStore(tmp_path / "s.json")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, make_deps(made_dirs=[]))
    # 測り直し: 🌊🎯と話す速さは、そのまま。音響(🎧の音量・突発音)と、それに連なる点だけが変わる
    cfg2 = {**cfg, "acoustic": {**cfg["acoustic"], "window_min": 1}}
    dirs = []
    new = pipeline.remeasure_acoustics(row, "https://x/a.mp3", "ja", cfg2, store, make_deps(made_dirs=dirs))
    assert new["calm_star"] == row["calm_star"] and new["interest_level"] == row["interest_level"]
    assert new["features"]["speech_rate"] == row["features"]["speech_rate"]
    assert len(new["features"]["timeline"]["volume_db"]) == 1          # 1分だけ測った
    assert new["features"]["duration_sec"] == row["features"]["duration_sec"]   # 回全体の長さは変わらない
    assert new["ear_star"] is not None and new["final_star"] is not None
    assert store.get("analysis", row["episode_id"])["features"]["timeline"]["volume_db"] == new["features"]["timeline"]["volume_db"]
    assert dirs and not any(os.path.exists(d) for d in dirs)           # 音声は残らない


def test_sudden_warning(cfg, tmp_path, caplog):
    with caplog.at_level(logging.WARNING, logger="neochi.pipeline"):
        pipeline.analyze_episode(SHOW, ep(9), cfg, JsonStore(tmp_path / "s.json"), make_deps(loud=True, made_dirs=[]))
    assert "突発音が異常値" in caplog.text


def test_llm_failure_still_gets_final_star(cfg, tmp_path):
    deps = make_deps(made_dirs=[])
    deps.judge = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("api down"))
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, JsonStore(tmp_path / "s.json"), deps)
    assert row["calm_star"] is None and row["final_star"] is not None


def test_rating_from_dummy_sleep_log(cfg, zcfg, tmp_path):
    from neochi import cli
    store = JsonStore(tmp_path / "s.json")
    pipeline.analyze_episode(SHOW, ep(1), cfg, store, make_deps(made_dirs=[]))
    e = ep(1).id
    before = store.get("analysis", e)["final_star"]
    for i, m in enumerate((12, 18, 25, 22, 40)):
        store.upsert("sleep_log", {"id": f"w{i}", "episode_id": e, "source": "watch", "latency_min": m})
    store.upsert("sleep_log", {"id": "s1", "episode_id": e, "source": "self", "latency_min": 3})  # 自己申告は入れない
    assert store.episode_watch_latencies(e) == [12, 18, 25, 22, 40]
    store.upsert("show", {"id": SHOW.id, "title": SHOW.title})
    cli._update_show_stars(store, [SHOW.id])
    cli.update_ratings(store, [SHOW.id], zcfg)
    show = store.get("show", SHOW.id)
    assert show["show_star"] == before
    assert (show["z_rank"] is not None) == (before >= zcfg["z"]["min_star"])


def test_session_judge_writes_pending_and_apply(tmp_path, cfg):
    from neochi import pipeline as pl
    from neochi.store import JsonStore
    store = JsonStore(tmp_path / "s.json")
    e = ep(1)
    deps = make_deps(made_dirs=[])
    deps.judge, deps.pending_dir = None, str(tmp_path / "pending")
    row = pl.analyze_episode(SHOW, e, cfg, store, deps)
    assert row["calm_star"] is None and (tmp_path / "pending" / f"{pl._safe(e.id)}.json").exists()
    new = pl.apply_judgement({"episode_id": e.id, "calm_star": 4, "interest_level": "mid", "reason": "淡々としています"}, cfg, store)
    assert new["calm_star"] == 4.0 and new["final_star"] is not None and new["interest_level"] == "mid"


def test_new_outputs_saved_from_api_and_session(tmp_path, cfg):
    from neochi import llm
    per = [0.2] * 20
    per[6] = 1.6
    j = {"interest": {k: {"score": 1, "min": 3} for k in "ABCDE"},
         "calm": {**{k: {"score": 0, "min": None} for k in "ABCD"}, "A": {"score": 1, "min": 6}},
         "calm_per_min": per, "moments": [{"min": 6, "note": "笑いで声が上ずる"}],
         "content_summary": "冬の布団の話です。後半はお便りを読みます。", "reason": "淡々としています"}
    # API で判定した回
    store = JsonStore(tmp_path / "s.json")
    deps = make_deps(made_dirs=[])
    deps.judge = lambda *a, **k: llm.parse_judgement(json.dumps(j, ensure_ascii=False))
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    assert row["calm_per_min"][6] == 1.6 and row["content_summary"].startswith("冬の布団")
    assert row["reasons"]["moments"] == [{"min": 6, "note": "笑いで声が上ずる", "level": 2}]
    assert row["interest_score"] == 5 and row["reasons"]["items"]["interest"]["A"]["score"] == 1
    # セッションで判定した回
    deps2 = make_deps(made_dirs=[])
    deps2.judge, deps2.pending_dir = None, str(tmp_path / "pending")
    row2 = pipeline.analyze_episode(SHOW, ep(2), cfg, store, deps2)
    assert "calm_per_min" not in row2 and "content_summary" not in row2     # 判定前は書かない(null のまま)
    new = pipeline.apply_judgement({**j, "episode_id": ep(2).id}, cfg, store)
    assert new["calm_per_min"] == per and new["reasons"]["moments"][0]["level"] == 2


def test_content_start_saved_and_opening_marks(tmp_path, cfg):
    spans = [(0, 8, "ジングル"), (65.4, 70, "こんばんは"), (400, 410, "後半")]
    assert pipeline.with_second_marks(spans) == "[0:00] ジングル\n[1:05] こんばんは"   # 5分+1分より後は入れない
    assert pipeline._new_outputs({"content_start": {"sec": 65, "anchor": "こんばんは"}}) == {
        "content_start_sec": 65, "content_start_anchor": "こんばんは"}
    assert pipeline._new_outputs({"content_start": {"sec": 0, "anchor": None}}) == {
        "content_start_sec": 0, "content_start_anchor": None}      # 0 = 冒頭から本編(判定した、という記録)
    assert pipeline._new_outputs({"content_start": None}) == {}      # 見つからないときは書かない(null のまま)
    # セッション判定: 取り込むと列に入る
    from neochi import llm
    store = JsonStore(tmp_path / "s.json")
    deps = make_deps(made_dirs=[])
    deps.judge, deps.pending_dir = None, str(tmp_path / "pending")
    pipeline.analyze_episode(SHOW, ep(4), cfg, store, deps)
    pending = json.loads((tmp_path / "pending" / f"{pipeline._safe(ep(4).id)}.json").read_text(encoding="utf-8"))
    assert "opening" in pending
    new = pipeline.apply_judgement({"episode_id": ep(4).id, "calm_star": 4, "interest_level": "mid", "reason": "淡々",
                                    "content_start": {"sec": 65, "anchor": "こんばんは"}}, cfg, store)
    assert "content_start_sec" not in new       # 旧形式の判定では、本編の開始は読まない
    j = {"interest": {k: {"score": 1, "min": 3} for k in "ABCDE"}, "calm": {k: {"score": 0, "min": None} for k in "ABCD"},
         "reason": "淡々", "content_start": {"sec": 65, "anchor": "こんばんは"}}
    new = pipeline.apply_judgement({**j, "episode_id": ep(4).id}, cfg, store)
    assert new["content_start_sec"] == 65 and new["content_start_anchor"] == "こんばんは"


def test_old_format_judgement_leaves_new_outputs_empty(tmp_path, cfg):
    store = JsonStore(tmp_path / "s.json")
    row = pipeline.analyze_episode(SHOW, ep(3), cfg, store, make_deps(made_dirs=[]))
    assert "calm_per_min" not in row and "content_summary" not in row


def test_shows_csv_genres_are_display_names():
    """genre は画面に出す系統だけ。集めた目的は cohort に分ける(docs/VOICE.md §7)。"""
    shows = feeds.load_shows("data/shows.csv")
    from neochi import genre

    assert {s.genre for s in shows} <= set(genre.GENRES)
    assert all(s.apple_category for s in shows)  # categorize で読み済み
    assert {s.cohort for s in shows} <= {"core", "popular", "control", "benchmark_en"}
    assert all(s.lang == "en" for s in shows if s.cohort == "benchmark_en")


def test_sync_shows_copies_genre_and_cohort(tmp_path, monkeypatch):
    from neochi import cli

    monkeypatch.delenv("SUPABASE_URL", raising=False)  # 本番の DB に書かないように
    monkeypatch.delenv("SUPABASE_SERVICE_KEY", raising=False)
    csv_path = tmp_path / "s.csv"
    csv_path.write_text("title,publisher,rss_url,genre,apple_category,cohort,lang\n"
                        "テスト番組,p,https://x/f,教養,History,control,ja\n"
                        "未登録,p,https://x/g,朗読,Arts>Books,core,ja\n", encoding="utf-8")
    store_path = tmp_path / "store.json"
    st = JsonStore(store_path)
    st.upsert("show", {"id": SHOW.id, "title": "テスト番組", "rss_url": SHOW.rss_url, "genre": "人気番組（一般）"})
    st.save()
    assert cli.main(["--store", str(store_path), "sync-shows", "--csv", str(csv_path)]) == 0
    rows = JsonStore(store_path).rows("show")
    assert len(rows) == 1  # 未登録の番組は足さない
    assert rows[0]["genre"] == "教養" and rows[0]["cohort"] == "control" and rows[0]["apple_category"] == "History"


def test_genre_from_apple_category():
    from neochi import genre

    assert genre.from_apple("Comedy>Improv") == "コメディ"
    assert genre.from_apple("History") == "教養"
    assert genre.from_apple("Society & Culture>Documentary") == "雑談"
    assert genre.from_apple(None) == "雑談"
    assert genre.resolve("寝落ち用", "Health & Fitness") == "寝落ち用"  # 手で書いた系統が優先
    assert genre.resolve("", "Comedy") == "コメディ"
    assert set(genre.APPLE_TO_GENRE.values()) <= set(genre.GENRES)
    assert not (genre.SLEEP_MADE & genre.NOT_SLEEP_MADE)


def test_parse_category():
    xml = (b'<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>'
           b'<itunes:category text="Comedy"><itunes:category text="Improv"/></itunes:category>'
           b'<itunes:category text="Arts"/></channel></rss>')
    assert feeds.parse_category(xml) == "Comedy>Improv"
    assert feeds.parse_category(b"<rss><channel></channel></rss>") is None


def _deps_with_spans():
    d = make_deps(made_dirs=[])
    spans = [(0.0, 20.0, "こんばんは、今夜の話です。"), (65.0, 80.0, "二分目の話です。")]
    d.transcribe = lambda path, dur, lang, cfg: ("こんばんは、今夜の話です。二分目の話です。", 2.0, spans)
    d.judge = None   # セッションで判定する(判定待ちとして書き出す)
    return d


def test_transcript_and_versions_are_saved(cfg, tmp_path):
    """文字起こしを保存し、どの定義で作った行かを記録する(定義を変えたとき、判定だけやり直せる)。"""
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    tr = store.get("transcript", row["episode_id"])
    assert tr["spans"][1] == [65.0, 80.0, "二分目の話です。"] and tr["version"] and tr["lang"] == "ja"
    v = row["reasons"]["versions"]
    assert v["transcript"] == tr["version"] and v["scoring"] and "rubric" not in v   # 判定待ちは、まだ基準で採点していない


def test_judgement_records_rubric_version_and_repending_finds_stale(cfg, tmp_path):
    import argparse
    import json

    from neochi import cli, versions
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    j = {"episode_id": row["episode_id"], "interest": {k: {"score": 1} for k in "ABCDE"}, "calm": {k: {"score": 0} for k in "ABCD"},
         "calm_per_min": [0.1] * 2, "moments": [], "reason": "穏やか"}
    # 判定の形は llm.parse_judgement が決める。通る形が分からないときは、版の記録だけを確かめる
    try:
        new = pipeline.apply_judgement(j, cfg, store)
    except (KeyError, ValueError):
        new = {**row, "reasons": {**row["reasons"], "versions": {**row["reasons"]["versions"], "rubric": versions.current(cfg)["rubric"]}}}
        store.upsert("analysis", new)
    assert new["reasons"]["versions"]["rubric"] == versions.current(cfg)["rubric"]
    # 基準が同じなら、判定し直しの対象にならない。版が違う(古い)回だけが対象
    store.upsert("episode", {"id": row["episode_id"], "show_id": SHOW.id, "title": "第1回"})
    store.upsert("show", {"id": SHOW.id, "title": SHOW.title})
    out = tmp_path / "re"
    args = lambda **k: argparse.Namespace(store=str(tmp_path / "s.json"), stale=True, episodes="", limit=0, pending=str(out), **k)
    store.save()
    assert cli.cmd_repending(args()) == 0 and not out.exists()
    a = store.get("analysis", row["episode_id"])
    a["reasons"]["versions"]["rubric"] = "old00000"
    store.save()
    assert cli.cmd_repending(args()) == 0
    files = list(out.glob("*.json"))
    assert len(files) == 1 and "[1分]" in json.loads(files[0].read_text(encoding="utf-8"))["transcript"]


def test_retranscribe_saves_transcript_without_changing_scores(cfg, tmp_path):
    """文字起こしを保存する前に解析した回を、点を変えずに、判定し直せるようにする。"""
    store = JsonStore(tmp_path / "s.json")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, make_deps(made_dirs=[]))   # spans なし = 文字起こしは保存されない
    assert store.get("transcript", row["episode_id"]) is None
    deps = _deps_with_spans()
    e = {"id": row["episode_id"], "audio_url": "https://x/a.mp3", "duration_sec": 600}
    assert pipeline.retranscribe_episode(e, "ja", 600, cfg, store, deps) is True
    assert store.get("transcript", row["episode_id"])["spans"][0][2] == "こんばんは、今夜の話です。"
    assert store.get("analysis", row["episode_id"])["final_star"] == row["final_star"]    # 点は変わらない


def test_trial_v2_prints_scores_next_to_old_ones(cfg, tmp_path, capsys):
    import argparse
    import json

    from neochi import cli
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    store.save()
    j = {"episode_id": row["episode_id"], "emotion": [], "worry": [], "hook": [], "follow": [],
         "imagery": [{"from": 0, "to": 19, "quote": "朝の市場です"}], "reason": "穏やかです"}
    f1, f2 = tmp_path / "r1.jsonl", tmp_path / "r2.jsonl"
    f1.write_text(json.dumps(j, ensure_ascii=False) + "\n", encoding="utf-8")
    f2.write_text(json.dumps({**j, "emotion": [{"min": 2, "kind": "negative", "strength": 2, "quote": "怖い"}]}, ensure_ascii=False) + "\n", encoding="utf-8")
    out = tmp_path / "o.json"
    a = argparse.Namespace(file=str(f1), file2=str(f2), set="", out=str(out), param=["calm.slope=0.5"])
    assert cli.cmd_trial_v2(a) == 0
    text = capsys.readouterr().out
    assert "判定のぶれ" in text and json.loads(out.read_text(encoding="utf-8"))[0]["calm"] == 5.0


def test_trial_v1_reports_judge_spread(cfg, tmp_path, capsys):
    """旧の基準の判定から、2人のぶれと、点の幅に対する割合を出す(v2 と同じ見方で比べるため)。"""
    import argparse
    import json

    from neochi import cli
    def j(eid, calm_scores, int_scores):
        return json.dumps({"episode_id": eid, "calm": {k: {"score": v, "min": None} for k, v in zip("ABCD", calm_scores)},
                           "interest": {k: {"score": v, "min": None} for k, v in zip("ABCDE", int_scores)}, "reason": "穏やかです"}, ensure_ascii=False)
    f1, f2 = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    f1.write_text(j("e1", [0, 0, 0, 0], [1, 1, 0, 1, 1]) + "\n" + j("e2", [2, 2, 1, 1], [0, 0, 0, 0, 1]) + "\n", encoding="utf-8")
    f2.write_text(j("e1", [0, 1, 0, 0], [1, 1, 0, 1, 1]) + "\n" + j("e2", [2, 2, 1, 1], [0, 1, 0, 0, 1]) + "\n", encoding="utf-8")
    assert cli.cmd_trial_v1(argparse.Namespace(file=str(f1), file2=str(f2), set="", out="")) == 0
    out = capsys.readouterr().out
    assert "判定のぶれ" in out and "ぶれ ÷ 幅" in out


def _v2_interest_judgement(eid, imagery=True):
    """🌊は旧の項目(A〜D)、🎯は観察(hook・follow・imagery)で出す、いまの判定の形式。"""
    return {"episode_id": eid,
            "hook": [], "follow": [{"from": 5, "to": 9, "quote": "前回の続きですが"}],
            "imagery": [{"from": 0, "to": 19, "quote": "朝の市場に着くと"}] if imagery else [],
            "calm": {k: {"score": 0, "min": None} for k in "ABCD"},
            "calm_per_min": [0.1] * 20, "moments": [], "reason": "穏やかです", "content_summary": "市場の朝の話です。"}


def test_interest_judged_by_observations_is_stored_and_scored_from_them(cfg, tmp_path):
    """🎯を観察で判定した回: 観察を reasons に残し、1〜10の点は付けず、🎯★は観察から計算して総合に入る。"""
    import json

    from neochi import observe
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    new = pipeline.apply_judgement(_v2_interest_judgement(row["episode_id"]), cfg, store)
    assert new["interest_score"] is None and new["interest_level"] in ("low", "mid", "high")
    obs = new["reasons"]["interest_obs"]
    assert obs["imagery"][0]["quote"] == "朝の市場に着くと" and obs["follow"][0]["from"] == 5
    ocfg = observe.load_config()
    istar = observe.interest_star(obs, ocfg)
    w = cfg["total"]["weights"]
    expect = round((w["interest"] * istar + w["calm"] * new["calm_star"] + w["ear"] * new["ear_star"]) / sum(w.values()), 1)
    assert new["total_star"] == expect
    # 保存済みの観察から、点を計算し直せる(observe.yaml の数値を直したときの、判定のやり直し不要の再計算)
    assert pipeline.restar_ai(new, cfg) == new["total_star"]
    assert new["reasons"]["versions"]["rubric"]


def test_missing_interest_arrays_are_rejected_not_scored_as_boring(cfg):
    """imagery を書き忘れた判定を、退屈として減点しない(空の配列で書かせる)。"""
    import json

    import pytest

    from neochi import llm
    j = _v2_interest_judgement("e1")
    del j["imagery"]
    with pytest.raises(ValueError):
        llm.parse_judgement(json.dumps(j, ensure_ascii=False), cfg)
    j["imagery"] = []
    assert llm.parse_judgement(json.dumps(j, ensure_ascii=False), cfg)["interest_level"] == "low"   # 具体的な話がない = 退屈側


def test_rejudging_with_old_format_drops_stale_observations(cfg, tmp_path):
    """旧の形式(項目 A〜E)で判定し直したときは、前の観察を引き継がない。"""
    import json
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    pipeline.apply_judgement(_v2_interest_judgement(row["episode_id"]), cfg, store)
    old = {"episode_id": row["episode_id"], "interest": {k: {"score": 1, "min": None} for k in "ABCDE"},
           "calm": {k: {"score": 0, "min": None} for k in "ABCD"}, "calm_per_min": [0.1] * 20, "moments": [], "reason": "穏やかです"}
    new = pipeline.apply_judgement(old, cfg, store)
    assert "interest_obs" not in new["reasons"] and new["interest_score"] == 5


def test_site_shows_interest_observations_with_quotes():
    from neochi import site
    h = site.interest_obs_body({"hook": [{"min": 2, "quote": "実はこのあと"}],
                                "follow": [{"from": 5, "to": 9, "quote": "前回の続きですが"}],
                                "imagery": [{"from": 0, "to": 9, "quote": "朝の市場に着くと"}]})
    assert "10分 / 20分" in h and "5分" in h and "1件" in h and "朝の市場に着くと" in h and "5〜9分" in h


def test_site_interest_gauge_marks_current_zone_and_bars():
    from neochi import site
    h = site.interest_obs_body({"hook": [], "follow": [], "imagery": [{"from": 0, "to": 9, "quote": "朝の市場に着くと"}]}, level="mid")
    assert 'class="zone3"' in h and '<span class="on">ちょうどよい</span>' in h
    assert h.count('class="gauge"') == 3 and "width:50%" in h   # 具体的な話 10分 / 20分


def test_transcript_is_saved_after_the_episode_exists(cfg, tmp_path):
    """transcript 表は episode を参照する(本番の DB)。新しい回で、先に文字起こしを保存すると、参照先がなく失敗する。
    回を登録したあとに保存することを、参照の制約つきの保存先で確かめる。"""
    class FkStore(JsonStore):
        def upsert(self, table, row):
            if table == "transcript" and self.get("episode", row["episode_id"]) is None:
                raise RuntimeError("foreign key violation")
            return super().upsert(table, row)
    store = FkStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    assert store.get("transcript", row["episode_id"]) is not None


def _calm_obs_judgement(eid):
    return {"episode_id": eid, "version": 2,
            "emotion": [{"min": 3, "kind": "negative", "strength": 2, "quote": "怖い話をします"}],
            "worry": [{"min": 5, "topic": "money", "quote": "生活費が心配で"}],
            "hook": [], "follow": [], "load": [{"from": 6, "to": 9, "quote": "数字が次々に出てきて"}],
            "imagery": [{"from": 0, "to": 12, "quote": "朝の市場に着くと"}],
            "content_summary": "市場を歩く話です。", "reason": "穏やかな語りです。"}


def test_calm_observations_make_star_curve_and_moments_together(cfg, tmp_path):
    """🌊も観察で出す形式: ★・1分ごとの線・山は、同じ観察から作る(別々に書かないので、食い違わない)。"""
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    new = pipeline.apply_judgement(_calm_obs_judgement(row["episode_id"]), cfg, store)
    obs = new["reasons"]["calm_obs"]
    assert len(obs["emotion"]) == 1 and len(obs["worry"]) == 1 and obs["load"][0]["from"] == 6
    assert not new["reasons"].get("items")   # 4項目の点は、付けない(観察から作るので)
    assert new["calm_per_min"][3] > 0 and new["calm_per_min"][5] > 0 and new["calm_per_min"][0] == 0
    assert [m["min"] for m in new["reasons"]["moments"]] == [3, 5] and new["reasons"]["moments"][0]["level"] == 2
    assert 1.0 <= new["calm_star"] < 5.0
    assert new["interest_level"] in ("low", "mid", "high") and new["interest_score"] is None


def test_calm_observation_arrays_must_all_be_present():
    import pytest

    from neochi import llm
    j = _calm_obs_judgement("x")
    del j["load"]
    with pytest.raises(ValueError):
        llm.parse_judgement(json.dumps(j, ensure_ascii=False))


def test_recalm_recomputes_everything_from_observations(cfg, tmp_path):
    """observe.yaml の数値を変えたとき、観察から、★・線・山・🎯のレベルを計算し直す(判定はやり直さない)。"""
    store = JsonStore(tmp_path / "s.json")
    deps = _deps_with_spans()
    deps.pending_dir = str(tmp_path / "pending")
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, store, deps)
    new = pipeline.apply_judgement(_calm_obs_judgement(row["episode_id"]), cfg, store)
    stale = {**new, "calm_star": 1.0, "calm_per_min": [9.0] * 20, "interest_level": "high"}
    fresh = pipeline.recalm(stale, cfg)
    assert fresh["calm_star"] == new["calm_star"] and fresh["calm_per_min"] == new["calm_per_min"]
    assert fresh["interest_level"] == new["interest_level"]


def test_site_calm_observations_show_gauges_and_quotes():
    from neochi import site
    h = site.calm_obs_body({"emotion": [{"min": 3, "kind": "negative", "strength": 2, "quote": "怖い話をします"}],
                            "worry": [], "load": [{"from": 6, "to": 9, "quote": "数字が次々に出てきて"}]})
    assert "怖い話をします" in h and "不安・緊迫" in h and "1件" in h and "4分 / 20分" in h and h.count('class="gauge"') == 3


def test_repending_shard_is_stable_while_judging_progresses(cfg, tmp_path):
    """並列に判定し直すとき、分担は文字起こしのある回の並びで決まる。判定が進んで古い回が減っても、分担はずれない。"""
    import argparse

    from neochi import cli
    store = JsonStore(tmp_path / "s.json")
    store.upsert("show", {"id": SHOW.id, "title": SHOW.title})
    ids = []
    for k in range(1, 5):
        deps = _deps_with_spans()
        deps.pending_dir = str(tmp_path / "p0")
        row = pipeline.analyze_episode(SHOW, ep(k), cfg, store, deps)
        ids.append(row["episode_id"])
    store.save()
    def run(shard):
        out = tmp_path / f"out{shard.replace('/', '_')}"
        args = argparse.Namespace(store=str(tmp_path / "s.json"), stale=True, episodes="", limit=0, pending=str(out), shard=shard)
        assert cli.cmd_repending(args) == 0
        return {p.stem for p in out.glob("*.json")} if out.exists() else set()
    a, b = run("0/2"), run("1/2")
    assert a | b == set(ids) and not (a & b) and len(a) == 2
