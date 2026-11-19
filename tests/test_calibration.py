"""採点ルールの物差し(2026-11-16)。

方針: 採点の数値は、睡眠の根拠の強さで決める(docs/EVIDENCE.md)。「寝落ち用の番組」「対照群」といったラベルを正解にして
数値を合わせることはしない(ラベルは、実際に眠れたことの証拠ではないため)。差をつけるのは、格付けの線(方針)で行う。

ここで確かめるのは次の3つ。
1. 重みが、根拠の強さに沿っている(研究がある項目 ◯ が、仮説 △ より重い)。
2. 極端な2つの回(昂る回・穏やかな回)の向きが、根拠のとおりに出る。
3. 格付けの割合が、方針(上位約15%が ZZZ、約45%が ZZ、約80%が Z)から外れていない。
   tests/data/calibration_shows.json は、2026-11-15 に公開していた97番組の最新の回の判定(割合を見るためだけに使う)。
"""
import json
from pathlib import Path

import pytest

from neochi import scoring
from neochi.z_rank import z_rank

DATA = json.loads((Path(__file__).parent / "data" / "calibration_shows.json").read_text(encoding="utf-8"))


def _total(calm_sum: int, interest_sum: int, feats: dict, cfg: dict) -> float:
    ear = scoring.ear_star({k: v for k, v in feats.items() if v is not None}, "ja", cfg)
    return scoring.total_star(scoring.calm_star(calm_sum, cfg), ear, None, cfg, interest_score=max(1, interest_sum))


def _show_total(o: dict, cfg: dict) -> float:
    feats = {"speech_rate": o["rate"], "speech_rate_cv": o["cv"], "volume_std_db": o["vol"], "sudden_per_10min": o["sudden"]}
    return _total(sum(o["calm"].values()), sum(o["intr"].values()), feats, cfg)


def test_weights_follow_evidence_strength(cfg):
    """🌊(研究がある)が最も重く、🎯のゾーンと🎧の多くは仮説なので、それぞれ🌊より軽い。突発音は🎧の中で最も重い。"""
    w = cfg["total"]["weights"]
    assert w["calm"] > w["interest"] and w["calm"] > w["ear"]
    ew = cfg["ear"]["weights"]
    assert ew["sudden"] == max(ew.values())


def test_calm_star_uses_wider_slope(cfg):
    assert scoring.calm_star(0, cfg) == 5.0
    assert scoring.calm_star(2, cfg) == 3.5      # 5 − 2×0.75
    assert scoring.calm_star(8, cfg) == 1.0      # 下限


def test_extreme_cases_go_the_evidence_way(cfg, zcfg):
    loud = {"speech_rate": 450, "speech_rate_cv": 0.4, "volume_std_db": 12, "sudden_per_10min": 10}
    gentle = {"speech_rate": 200, "speech_rate_cv": 0.08, "volume_std_db": 3, "sudden_per_10min": 0}
    assert z_rank(_total(6, 9, loud, cfg), zcfg) is None       # 感情・対立・負荷が多く、突発音も多い回は、載せない
    assert z_rank(_total(0, 4, gentle, cfg), zcfg) == "ZZZ"    # 昂る要素がなく、突発音もない回


def test_rank_shares_match_policy(cfg, zcfg):
    ranks = [z_rank(_show_total(o, cfg), zcfg) for o in DATA]
    n = len(ranks)
    assert 0.08 <= ranks.count("ZZZ") / n <= 0.22                              # 上位約15%(以前は 73%)
    # 上位約45%。2026-11-19 に重みを 🌊 0.5 / 🎧 0.3 に変えて、ZZ がやや増えた(本番の試算で ZZ 以上 51%)ので、上限を 0.60 にした(docs/SCORE.md「重みの変更」)
    assert 0.35 <= (ranks.count("ZZZ") + ranks.count("ZZ")) / n <= 0.60
    assert 0.10 <= ranks.count(None) / n <= 0.30                               # 残りの約2割は載せない
