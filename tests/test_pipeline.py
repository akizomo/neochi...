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
         "calm": {k: {"score": 0, "min": None} for k in "ABCD"},
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


def test_old_format_judgement_leaves_new_outputs_empty(tmp_path, cfg):
    store = JsonStore(tmp_path / "s.json")
    row = pipeline.analyze_episode(SHOW, ep(3), cfg, store, make_deps(made_dirs=[]))
    assert "calm_per_min" not in row and "content_summary" not in row
