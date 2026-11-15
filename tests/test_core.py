import json
import pytest
import numpy as np

from neochi import features, feeds, llm, scoring, strings, transcribe
from neochi.z_rank import z_rank


def test_sleep_comment_boundaries():
    assert strings.sleep_comment(4.9) == "即落ちでした"
    assert strings.sleep_comment(9.9) == "即落ちでした"
    assert strings.sleep_comment(10) == "理想の寝落ちでした"
    assert strings.sleep_comment(20) == "やや粘りました"
    assert strings.sleep_comment(30) == "最後まで聴いてしまいました"
    assert "―" in strings.sleep_line(None)


def test_sudden_sound_counts_loud_jumps(cfg):
    sr = 8000
    x = (np.random.default_rng(0).normal(0, 0.01, sr * 600)).astype(np.float32)  # 10分の静かな音
    for sec in (100, 200, 300):  # 1秒だけ大きな音を3回
        x[sec * sr:(sec + 1) * sr] *= 20
    f = features.acoustic_features(x, sr, cfg)
    assert f["sudden_per_10min"] == 3
    assert abs(f["duration_sec"] - 600) < 1


def test_sustained_loud_passage_is_not_sudden(cfg):
    sr = 8000
    x = np.random.default_rng(2).normal(0, 0.01, sr * 600).astype(np.float32)
    x[300 * sr:] *= 20          # 5分から、ずっと大きい(急に大きくなって、そのまま)
    f = features.acoustic_features(x, sr, cfg)
    # 切り替わりの1回だけ。大きい区間のあいだ、毎秒を突発音と数えない
    assert f["sudden_per_10min"] <= 1 / 10 * 10 + 1e-6


def test_acoustics_measure_only_first_30_minutes(cfg):
    sr = 8000
    rng = np.random.default_rng(1)
    x = rng.normal(0, 0.01, sr * 2400).astype(np.float32)   # 40分の静かな音
    for sec in (100, 200, 1900, 2000, 2100):                 # 突発音: 30分以内に2回、30分より後に3回
        x[sec * sr:(sec + 1) * sr] *= 20
    f = features.acoustic_features(x, sr, cfg)
    assert abs(f["duration_sec"] - 2400) < 1                 # 長さは、回全体
    assert abs(f["sudden_per_10min"] - 2 / 30 * 10) < 1e-6   # 30分で2回 = 10分あたり 0.67 回
    assert len(f["timeline"]["volume_db"]) == 30             # 音量の推移も、冒頭30分
    assert all(s < 1800 for s in f["timeline"]["sudden_at_sec"])


def test_speech_rate_units():
    r, u = features.speech_rate("こんにちは、今夜も静かに。", "ja", 1)
    assert u == "chars_per_min" and r == 11
    r, u = features.speech_rate("one two three four", "en", 2)
    assert u == "words_per_min" and r == 2


def test_ear_star_and_totals(cfg):
    calm = {"speech_rate": 250, "speech_rate_cv": 0.1, "volume_std_db": 4, "sudden_per_10min": 0}
    loud = {"speech_rate": 450, "speech_rate_cv": 0.4, "volume_std_db": 12, "sudden_per_10min": 10}
    assert scoring.ear_star(calm, "ja", cfg) == 5.0
    assert scoring.ear_star(loud, "ja", cfg) == 1.0
    assert scoring.ear_star({}, "ja", cfg) is None
    assert scoring.total_star(5, 5, "mid", cfg) == 5.0
    assert scoring.total_star(None, None, None, cfg) is None
    assert scoring.total_star(4, None, None, cfg) == 4.0  # 欠けた要素は除いて再配分


def test_final_star_ai_only(cfg):
    assert scoring.final_star(4.0, cfg) == (4.0, None)
    assert scoring.final_star(None, cfg) == (None, None)


def test_crowd_blends_into_content_axes_only(cfg):
    # AI解析: 🎯 引き込み力2(🎯★3.7)、🌊 5.0、🎧 4.0
    base = scoring.total_star(5.0, 4.0, None, cfg, 2)
    # みんなの評価は10件未満なら入れない
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, calm_votes=[1] * 9) == base
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, interest_votes=[0] * 9) == base
    # 🌊: みんなが低く付けると、総合が下がる。🎯: 「ちょうどよかった」が多いと、上がる
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, calm_votes=[1] * 20) < base
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, interest_votes=[0] * 20) > base
    # 🎧 には、みんなの評価を足さない(votes を渡しても、🎧の点は計算値のまま)
    assert scoring.blend_axis(4.0, 1.0, 5, cfg) == 4.0


def test_crowd_weight_is_capped_per_axis(cfg):
    w_small = scoring.blend_axis(5.0, 1.0, 10, cfg)
    w_big = scoring.blend_axis(5.0, 1.0, 1000, cfg)
    assert w_big < w_small
    assert abs(w_big - (5.0 * 0.5 + 1.0 * 0.5)) < 0.05   # 上限 0.5


def test_interest_vote_star_matches_zone_ends(cfg):
    assert scoring.interest_vote_star(0, cfg) == 5.0   # ちょうどよかった
    assert scoring.interest_vote_star(-1, cfg) == 3.0  # 退屈だった(ゾーンの低い側の端)
    assert scoring.interest_vote_star(1, cfg) == 1.0   # 聴き入った(引き込まれすぎの端)


def test_final_star_watch(cfg):
    # 実測は3件未満なら入れない
    assert scoring.final_star(4.5, cfg, 40, 2) == (4.5, None)
    # 実測3件・中央値40分(実測点 1.0)で、AI解析 4.5 から下がる。理由に「実測」が入る
    f, reason = scoring.final_star(4.5, cfg, 40, 3)
    assert f < 4.5 and reason and "実測" in reason
    # 実測が短いほど高い。10分以下は 5.0、40分以上は 1.0
    assert scoring.watch_star(5, cfg) == 5.0 and scoring.watch_star(45, cfg) == 1.0
    assert scoring.watch_star(25, cfg) == 3.0
    # 件数が増えるほど実測に寄る(上限 0.6)
    f3, _ = scoring.final_star(4.5, cfg, 40, 3)
    f50, _ = scoring.final_star(4.5, cfg, 40, 50)
    assert f50 < f3 and f50 >= round(4.5 * 0.4 + 1.0 * 0.6, 1) - 0.05


def test_z_rank(zcfg):
    assert z_rank(None, zcfg) is None
    assert z_rank(2.9, zcfg) is None              # 基準未満は掲載しない
    assert z_rank(3.0, zcfg) == "Z"
    assert z_rank(3.6, zcfg) == "ZZ"
    assert z_rank(4.2, zcfg) == "ZZZ"             # AI解析だけでも付く(実測の件数は条件にしない)


def test_z_rank_demote_needs_watch(zcfg):
    assert z_rank(3.2, zcfg, current="ZZZ", watch_n=4) == "ZZZ"   # 実測5件未満は下げない
    assert z_rank(3.2, zcfg, current="ZZZ", watch_n=5) == "Z"
    assert z_rank(2.0, zcfg, current="Z", watch_n=2) == "Z"
    assert z_rank(4.5, zcfg, current="Z", watch_n=0) == "ZZZ"      # 上がるのは、いつでも
