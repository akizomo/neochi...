"""採点ルールの較正(2026-11-16)。格付けが甘くなり、ほとんどの番組が ZZZ になったので、物差しを置く。

tests/data/calibration_shows.json は、2026-11-15 に公開していた97番組の、最新の回の判定(🌊🎯の項目の点と音響の測定値)。
cohort=control は、寝落ち用ではない教養トークの番組(対照群)。core は寝落ち用の番組。
人の手で個別の番組を動かすためではなく、ルール(config/scoring.yaml と z_rank.yaml)を変えたときに、
格付けがまた甘くなっていないかを確かめるための目安。回の平均ではなく1回ぶんなので、番組の評点よりばらつきが大きい。
"""
import json
from pathlib import Path

import pytest

from neochi import scoring
from neochi.z_rank import z_rank

DATA = json.loads((Path(__file__).parent / "data" / "calibration_shows.json").read_text(encoding="utf-8"))


def _total(o: dict, cfg: dict) -> float:
    feats = {"speech_rate": o["rate"], "speech_rate_cv": o["cv"], "volume_std_db": o["vol"], "sudden_per_10min": o["sudden"]}
    ear = scoring.ear_star({k: v for k, v in feats.items() if v is not None}, "ja", cfg)
    calm = 5 - 0.5 * sum(o["calm"].values())
    return scoring.total_star(calm, ear, None, cfg, interest_score=max(1, sum(o["intr"].values())))


@pytest.fixture(scope="module")
def scored(cfg):
    return [(o, _total(o, cfg)) for o in DATA]


def test_most_shows_are_not_top_rank(scored, zcfg):
    ranks = [z_rank(v, zcfg) for _, v in scored]
    assert ranks.count("ZZZ") / len(ranks) <= 0.25     # 以前は 73%
    assert ranks.count(None) / len(ranks) <= 0.10      # 載せられる番組が、極端に減らない


def test_control_ranks_below_sleep_shows_on_average(scored):
    core = [v for o, v in scored if o["cohort"] == "core"]
    ctl = [v for o, v in scored if o["cohort"] == "control"]
    assert sum(core) / len(core) > sum(ctl) / len(ctl)


def test_clearly_exciting_control_shows_do_not_reach_zz(scored, zcfg):
    """対照群のうち、解析で明らかに起伏・引き込みの強かった番組(ゆる言語学・ゆる天文学)は、ZZ に届かない。"""
    hit = [(o["title"], v) for o, v in scored if o["cohort"] == "control" and ("言語学" in o["title"] or "天文学" in o["title"])]
    assert len(hit) == 2
    assert all(z_rank(v, zcfg) in (None, "Z") for _, v in hit)
