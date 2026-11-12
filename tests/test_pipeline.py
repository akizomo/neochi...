import contextlib
import logging
import os
import tempfile

import numpy as np

from neochi import feeds, pipeline, z_rank
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


def test_sudden_warning(cfg, tmp_path, caplog):
    with caplog.at_level(logging.WARNING, logger="neochi.pipeline"):
        pipeline.analyze_episode(SHOW, ep(9), cfg, JsonStore(tmp_path / "s.json"), make_deps(loud=True, made_dirs=[]))
    assert "突発音が異常値" in caplog.text


def test_llm_failure_still_gets_final_star(cfg, tmp_path):
    deps = make_deps(made_dirs=[])
    deps.judge = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("api down"))
    row = pipeline.analyze_episode(SHOW, ep(1), cfg, JsonStore(tmp_path / "s.json"), deps)
    assert row["calm_star"] is None and row["final_star"] is not None


def test_z_rank_from_dummy_sleep_log(cfg, zcfg, tmp_path):
    store = JsonStore(tmp_path / "s.json")
    pipeline.analyze_episode(SHOW, ep(1), cfg, store, make_deps(made_dirs=[]))
    e = ep(1).id
    for m in (12, 18, 25, 22, 40):
        store.upsert("sleep_log", {"id": f"w{m}", "episode_id": e, "source": "watch", "latency_min": m})
    store.upsert("sleep_log", {"id": "s1", "episode_id": e, "source": "self", "latency_min": 3})  # 自己申告は集計しない
    assert z_rank.z_rank(store.watch_latencies(SHOW.id), zcfg) == "ZZZ"
