import json
import pytest
import numpy as np

from neochi import features, feeds, llm, scoring, strings, transcribe
from neochi.z_rank import z_rank


def test_sleep_comment_boundaries():
    assert strings.sleep_comment(4.9) == "それは番組の力ではなく、ただの寝不足です"
    assert strings.sleep_comment(5) == "即落ちでした"
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


def test_final_star_ai_only_then_blend(cfg):
    assert scoring.final_star(4.0, None, 0, cfg) == (4.0, None)
    # みんなの評価は10件未満なら入れない
    assert scoring.final_star(4.5, 2.5, 9, cfg) == (4.5, None)
    f, reason = scoring.final_star(4.5, 2.5, 20, cfg)
    assert 2.5 < f < 4.5 and reason and "AI解析" in reason and "みんな" in reason
    f, reason = scoring.final_star(4.0, 3.8, 20, cfg)
    assert reason is None


def test_final_star_watch(cfg):
    # 実測は3件未満なら入れない
    assert scoring.final_star(4.5, None, 0, cfg, 40, 2) == (4.5, None)
    # 実測3件・中央値40分(実測点 1.0)で、AI解析 4.5 から下がる。理由に「実測」が入る
    f, reason = scoring.final_star(4.5, None, 0, cfg, 40, 3)
    assert f < 4.5 and reason and "実測" in reason
    # 実測が短いほど高い。10分以下は 5.0、40分以上は 1.0
    assert scoring.watch_star(5, cfg) == 5.0 and scoring.watch_star(45, cfg) == 1.0
    assert scoring.watch_star(25, cfg) == 3.0
    # 件数が増えるほど実測に寄る(上限 0.6)
    f3, _ = scoring.final_star(4.5, None, 0, cfg, 40, 3)
    f50, _ = scoring.final_star(4.5, None, 0, cfg, 40, 50)
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
