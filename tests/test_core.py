import numpy as np

from neochi import features, feeds, llm, scoring, strings, transcribe
from neochi.z_rank import z_rank


def test_sleep_comment_boundaries():
    assert strings.sleep_comment(4.9) == "それは番組の力ではなく、ただの寝不足です"
    assert strings.sleep_comment(5) == "即落ちでした"
    assert strings.sleep_comment(10) == "理想の寝落ちでした"
    assert strings.sleep_comment(20) == "やや粘りました"
    assert strings.sleep_comment(30) == "最後まで聞いてしまいました"
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
    f, reason = scoring.final_star(4.5, 2.5, 20, cfg)
    assert 2.5 < f < 4.5 and reason and "AI解析" in reason
    f, reason = scoring.final_star(4.0, 3.8, 20, cfg)
    assert reason is None


def test_z_rank(zcfg):
    assert z_rank([], zcfg) is None
    assert z_rank([45, 50], zcfg) is None          # 実測はあるが30分未満なし
    assert z_rank([10, 50, 60], zcfg) == "Z"
    assert z_rank([10, 20, 50], zcfg) == "ZZ"      # 2/3 ≥ 半分
    assert z_rank([10, 12, 15, 20, 25], zcfg) == "ZZZ"
    assert z_rank([10, 12, 15, 20], zcfg) == "ZZ"  # 件数が足りない


def test_plan_segments(cfg):
    assert transcribe.plan_segments(600, cfg) == [(0.0, 600)]
    segs = transcribe.plan_segments(3600, cfg)
    assert segs[0] == (0.0, 1200.0) and 1200 <= segs[1][0] <= 3300 and segs[1][1] == 300


def test_rate_is_plateau_not_slower_is_better(cfg):
    slow = scoring.ear_star({"speech_rate": 150}, "ja", cfg)
    ok = scoring.ear_star({"speech_rate": 290}, "ja", cfg)
    fast = scoring.ear_star({"speech_rate": 400}, "ja", cfg)
    assert slow == ok == 5.0 and fast < ok


def test_rate_profile_weights_front(cfg):
    # 前半(0〜10分)はゆっくり、中盤は速い。前半の重みが大きいので、単純平均より遅く出る
    spans = [(m * 60, m * 60 + 60, "あ" * 200) for m in range(10)] + [(m * 60, m * 60 + 60, "あ" * 400) for m in range(30, 35)]
    p = features.rate_profile(spans, "ja", cfg)
    simple = (200 * 10 + 400 * 5) / 15
    assert p["speech_rate"] < simple
    assert p["speech_rate_cv"] > 0


def test_parse_judgement_validates():
    j = llm.parse_judgement('前置き {"calm_star": 4.2, "interest_level": "mid", "reason": "淡々としています"} ')
    assert j["calm_star"] == 4.0 and j["interest_level"] == "mid"
    for bad in ('{"calm_star": 9, "interest_level": "mid"}', "なし", '{"calm_star": 3, "interest_level": "x"}'):
        try:
            llm.parse_judgement(bad)
        except (ValueError, KeyError):
            continue
        raise AssertionError(bad)


RSS = b"""<?xml version="1.0"?><rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<item><title>old</title><guid>a</guid><pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
<enclosure url="https://x/a.mp3"/><itunes:duration>10:30</itunes:duration></item>
<item><title>new</title><guid>b</guid><pubDate>Tue, 02 Jan 2024 00:00:00 +0000</pubDate>
<enclosure url="https://x/b.mp3"/></item><item><title>no audio</title></item></channel></rss>"""


def test_parse_feed_newest_first_and_stable_ids():
    sid = feeds.show_id("https://x/feed")
    eps = feeds.parse_feed(RSS, sid)
    assert [e.title for e in eps] == ["new", "old"]
    assert eps[1].duration_sec == 630
    assert [e.id for e in feeds.parse_feed(RSS, sid)] == [e.id for e in eps]
