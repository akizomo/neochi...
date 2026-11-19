import json

import pytest

from neochi import observe, textfeatures


@pytest.fixture
def ocfg():
    return observe.load_config()


def raw(**k):
    base = {"emotion": [], "worry": [], "hook": [], "follow": [], "imagery": [], "reason": "穏やかです"}
    return json.dumps({**base, **k}, ensure_ascii=False)


def test_observations_without_quote_or_with_bad_values_are_dropped(ocfg):
    o = observe.parse_observations(raw(
        emotion=[{"min": 3, "kind": "negative", "strength": 2, "quote": "怖い話です"},
                 {"min": 4, "kind": "negative", "strength": 2, "quote": ""},      # 引用なし
                 {"min": 25, "kind": "negative", "strength": 1, "quote": "x"},    # 範囲外の分
                 {"min": 5, "kind": "joy", "strength": 1, "quote": "x"},          # 不明な種類
                 {"min": 6, "kind": "conflict", "strength": 3, "quote": "x"}],    # 不明な強さ
        imagery=[{"from": 4, "to": 2, "quote": "x"}, {"from": 0, "to": 5, "quote": "朝の市場です"}]), ocfg)
    assert len(o["emotion"]) == 1 and len(o["imagery"]) == 1 and o["dropped"] == 5


def test_no_json_is_an_error(ocfg):
    with pytest.raises(ValueError):
        observe.parse_observations("判定できません", ocfg)


def test_calm_star_goes_down_with_more_and_stronger_observations(ocfg):
    none = observe.parse_observations(raw(), ocfg)
    one = observe.parse_observations(raw(emotion=[{"min": 2, "kind": "negative", "strength": 1, "quote": "a"}]), ocfg)
    strong = observe.parse_observations(raw(emotion=[{"min": 2, "kind": "negative", "strength": 2, "quote": "a"}]), ocfg)
    assert observe.calm_star(none, None, ocfg) == 5.0
    assert observe.calm_star(none, None, ocfg) > observe.calm_star(one, None, ocfg) > observe.calm_star(strong, None, ocfg)


def test_excitement_counts_less_than_negative_and_late_counts_less_than_early(ocfg):
    ev = lambda kind, m: observe.parse_observations(raw(emotion=[{"min": m, "kind": kind, "strength": 2, "quote": "a"}]), ocfg)
    assert observe.calm_raw(ev("excitement", 2), None, ocfg) < observe.calm_raw(ev("negative", 2), None, ocfg)
    assert observe.calm_raw(ev("negative", 15), None, ocfg) < observe.calm_raw(ev("negative", 2), None, ocfg)


def test_calm_per_min_comes_from_observations(ocfg):
    o = observe.parse_observations(raw(emotion=[{"min": 3, "kind": "conflict", "strength": 2, "quote": "a"}],
                                       worry=[{"min": 3, "topic": "money", "quote": "b"}]), ocfg)
    p = observe.calm_per_min(o, ocfg)
    assert len(p) == 20 and p[3] > 1.0 and sum(p) == p[3]   # 観察のある分だけが高い


def test_interest_is_a_peak_not_a_plateau(ocfg):
    """具体性が足りない(退屈)ほども、引き込みすぎ(先が気になる・追い続ける)ほども、下がる。"""
    good = observe.parse_observations(raw(imagery=[{"from": 0, "to": 19, "quote": "a"}]), ocfg)
    bored = observe.parse_observations(raw(), ocfg)
    hooked = observe.parse_observations(raw(imagery=[{"from": 0, "to": 19, "quote": "a"}], follow=[{"from": 0, "to": 19, "quote": "b"}],
                                            hook=[{"min": 1, "quote": "c"}, {"min": 4, "quote": "d"}]), ocfg)
    assert observe.interest_star(good, ocfg) == 5.0
    assert observe.interest_star(bored, ocfg) < 3.0 and observe.interest_star(hooked, ocfg) < observe.interest_star(good, ocfg)


def test_load_density_counts_numbers_and_terms_not_plain_talk():
    plain = "今日はいい天気ですね。散歩に行きましょうか。お茶でも飲みましょう。" * 10
    dense = "2023年の売上は1200億円で、アルゴリズムとインフラのGDPへの影響を試算しました。" * 10
    assert textfeatures.load_density(plain) == 0.0 and textfeatures.load_density(dense) > 40
    assert textfeatures.load_density("") is None


def test_novelty_drops_when_the_same_talk_repeats():
    a = "今夜は静かな港町の朝市について、魚屋さんの話を聞いてみましょう。" * 3
    spans = [(0, 30, a), (60, 90, "全く別の話題として、山の天気と登山道の整備について詳しくお伝えしていきます。" * 2),
             (120, 150, "全く別の話題として、山の天気と登山道の整備について詳しくお伝えしていきます。" * 2)]
    n = textfeatures.novelty_per_min(spans)
    assert n[0] == 1.0 and n[1] > 0.5 and n[2] < 0.1 and n[5] is None
