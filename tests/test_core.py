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
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, interest_votes=[5] * 9) == base
    # 🌊: みんなが低く付けると、総合が下がる。🎯: 10段階の4〜6(ゾーン)が多いと、上がる
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, calm_votes=[1] * 20) < base
    assert scoring.total_star(5.0, 4.0, None, cfg, 2, interest_votes=[5] * 20) > base
    # 🎧 には、みんなの評価を足さない(votes を渡しても、🎧の点は計算値のまま)
    assert scoring.blend_axis(4.0, 1.0, 5, cfg) == 4.0


def test_crowd_weight_is_capped_per_axis(cfg):
    w_small = scoring.blend_axis(5.0, 1.0, 10, cfg)
    w_big = scoring.blend_axis(5.0, 1.0, 1000, cfg)
    assert w_big < w_small
    assert abs(w_big - (5.0 * 0.5 + 1.0 * 0.5)) < 0.05   # 上限 0.5


def test_interest_rating_uses_the_same_zone_as_ai(cfg):
    # みんなの10段階は、AIの🎯と同じゾーンの式に通す
    base = scoring.total_star(5.0, 4.0, None, cfg, 5)
    assert scoring.total_star(5.0, 4.0, None, cfg, 5, interest_votes=[5] * 20) == base
    assert scoring.total_star(5.0, 4.0, None, cfg, 5, interest_votes=[10] * 20) < base   # 引き込まれすぎ
    assert scoring.total_star(5.0, 4.0, None, cfg, 5, interest_votes=[1] * 20) < base    # 退屈


def test_legacy_three_choice_keeps_the_same_stars(cfg):
    f = scoring.interest_rating_from_vote
    assert [scoring.interest_star(f(v, cfg), cfg) for v in (-1, 0, 1)] == [3.0, 5.0, 1.0]


def test_final_star_watch(cfg):
    # 実測は3件未満なら入れない
    assert scoring.final_star(4.5, cfg, 40, 2) == (4.5, None)
    # 実測3件・中央値40分(実測点 1.0)で、AI解析 4.5 から下がる。理由に「実測」が入る
    f, reason = scoring.final_star(4.5, cfg, 40, 3)
    assert f < 4.5 and reason and "実測" in reason
    # 実測が短いほど高い。10分以下は 5.0、40分以上は 1.0
    assert scoring.watch_star(5, cfg) == 5.0 and scoring.watch_star(60, cfg) == 1.0
    assert scoring.watch_star(37.5, cfg) == 3.0
    # 件数が増えるほど実測に寄る(上限 0.6)
    f3, _ = scoring.final_star(4.5, cfg, 40, 3)
    f50, _ = scoring.final_star(4.5, cfg, 40, 50)
    assert f50 < f3 and f50 >= round(4.5 * 0.4 + 1.0 * 0.6, 1) - 0.05


def test_z_rank(zcfg):
    assert z_rank(None, zcfg) is None
    assert z_rank(3.5, zcfg) is None              # 基準未満は掲載しない
    assert z_rank(3.6, zcfg) == "Z"
    assert z_rank(4.1, zcfg) == "ZZ"
    assert z_rank(4.5, zcfg) == "ZZZ"             # AI解析だけでも付く(実測の件数は条件にしない)


def test_z_rank_follows_star_both_ways(zcfg):
    assert z_rank(3.7, zcfg) == "Z"      # 評点が下がれば、格付けもすぐ下がる(格下げの保留はしない)
    assert z_rank(3.5, zcfg) is None
    assert z_rank(4.5, zcfg) == "ZZZ"    # 上がるのも、いつでも


def _judgement(**extra):
    base = {"interest": {k: {"score": 1, "min": 3} for k in "ABCDE"},
            "calm": {k: {"score": 0, "min": None} for k in "ABCD"}, "reason": "淡々としています"}
    return json.dumps({**base, **extra}, ensure_ascii=False)


def test_calm_per_min_is_clamped_and_rounded():
    calm = {**{k: {"score": 0, "min": None} for k in "ABCD"}, "A": {"score": 2, "min": 1}}   # 1分の山と合う
    v = llm.parse_judgement(_judgement(calm=calm, calm_per_min=[0.04, 2.7, -1, 1.25] + [0.2] * 20))
    assert v["calm_per_min"][:4] == [0.0, 2.0, 0.0, 1.2] and len(v["calm_per_min"]) == 20
    assert llm.parse_judgement(_judgement(calm_per_min=["x"]))["calm_per_min"] is None
    assert llm.parse_judgement(_judgement())["calm_per_min"] is None


def test_moments_come_from_calm_peaks():
    per = [0.2] * 20
    per[6], per[14], per[17] = 1.6, 1.1, 0.9          # 山は6分(多い)と14分(少し)。17分は1.0未満で山ではない
    notes = [{"min": 7, "note": "笑いで声が上ずる"}, {"min": 14, "note": "話題が急に変わる"}, {"min": 17, "note": "x"},
             {"min": 2, "note": "山ではない"}]
    calm = {"A": {"score": 2, "min": 6}, "B": {"score": 0, "min": None}, "C": {"score": 0, "min": None},
            "D": {"score": 1, "min": 14}}
    v = llm.parse_judgement(_judgement(calm=calm, calm_per_min=per, moments=notes))
    assert v["moments"] == [{"min": 6, "note": "笑いで声が上ずる", "level": 2},
                            {"min": 14, "note": "話題が急に変わる", "level": 1}]


def test_peak_without_note_is_dropped_and_max_three():
    per = [0.0, 1.2, 0.0, 1.4, 0.0, 1.6, 0.0, 1.8, 0.0, 1.1]
    notes = [{"min": m, "note": f"{m}分"} for m in (1, 3, 5, 7)]
    out = llm.calm_peaks(per, notes)
    assert [m["min"] for m in out] == [3, 5, 7]          # 高い順に3件、分の順に並べる
    assert llm.calm_peaks(per, []) == []


def test_flat_peak_counts_once():
    assert [m["min"] for m in llm.calm_peaks([0, 1.5, 1.5, 0], [{"min": 1, "note": "a"}, {"min": 2, "note": "b"}])] == [1]


def test_content_start_validation():
    ok = llm.parse_judgement(_judgement(content_start={"sec": 94.6, "anchor": "  こんばんは、\n今夜は  "}))["content_start"]
    assert ok == {"sec": 95, "anchor": "こんばんは、 今夜は"}
    assert llm.parse_judgement(_judgement(content_start={"sec": 0}))["content_start"] == {"sec": 0, "anchor": None}
    long = llm.parse_judgement(_judgement(content_start={"sec": 10, "anchor": "あ" * 60}))["content_start"]
    assert len(long["anchor"]) == 40
    # 一言のない秒、冒頭5分より後、負、真偽値、形が違うものは保存しない(飛ばさないほうが安全)
    for bad in ({"sec": 30}, {"sec": 301, "anchor": "x"}, {"sec": -1, "anchor": "x"}, {"sec": True, "anchor": "x"}, "95", [95]):
        assert llm.parse_judgement(_judgement(content_start=bad))["content_start"] is None
    assert llm.parse_judgement(_judgement())["content_start"] is None


def test_content_summary_limits():
    ok = "冬に布団を買い替えた話から、実家の毛布の思い出へ移ります。後半はお便りを2通読みます。"
    assert llm.parse_judgement(_judgement(content_summary=ok))["content_summary"] == ok
    assert llm.parse_judgement(_judgement(content_summary="あ" * 121))["content_summary"] is None
    assert llm.parse_judgement(_judgement(content_summary="驚きの結末！"))["content_summary"] is None
    assert llm.parse_judgement(_judgement())["content_summary"] is None


def test_curve_that_contradicts_items_is_dropped():
    calm_zero = {k: {"score": 0, "min": None} for k in "ABCD"}
    per = [0.2] * 20
    per[6] = 1.8                                   # 「多い」の山があるのに、4項目はすべて 0
    assert llm.parse_judgement(_judgement(calm=calm_zero, calm_per_min=per))["calm_per_min"] is None
    calm_a = {**calm_zero, "A": {"score": 2, "min": 12}}
    flat = [0.1] * 20                              # 12分に「多い」を付けたのに、線は平ら
    assert llm.parse_judgement(_judgement(calm=calm_a, calm_per_min=flat))["calm_per_min"] is None
    ok = [0.1] * 20
    ok[12] = 1.6
    assert llm.parse_judgement(_judgement(calm=calm_a, calm_per_min=ok))["calm_per_min"][12] == 1.6


def test_z_rank_cleared_when_not_judged(zcfg):
    assert z_rank(None, zcfg) is None   # 判定待ちは、格付けを付けない


def test_show_star_uses_judged_episodes_only(cfg, tmp_path):
    from neochi import cli
    from neochi.store import JsonStore
    s = JsonStore(tmp_path / "s.json")
    s.upsert("show", {"id": "sh", "title": "t", "show_star": 4.8, "z_rank": "ZZZ", "listing_status": "listed"})
    s.upsert("episode", {"id": "e1", "show_id": "sh"})
    s.upsert("episode", {"id": "e2", "show_id": "sh"})
    s.upsert("analysis", {"episode_id": "e1", "final_star": 4.8, "ear_star": 4.8})            # 耳だけ
    cli._update_show_stars(s, ["sh"])
    cli.update_ratings(s, ["sh"], yaml_z())
    assert s.get("show", "sh")["show_star"] is None and s.get("show", "sh")["listing_status"] == "researching"
    s.upsert("analysis", {"episode_id": "e2", "final_star": 3.7, "calm_star": 4.0, "interest_level": "mid"})
    cli._update_show_stars(s, ["sh"])
    cli.update_ratings(s, ["sh"], yaml_z())
    assert s.get("show", "sh")["show_star"] == 3.7 and s.get("show", "sh")["z_rank"] == "Z"


def yaml_z():
    from neochi import cli
    return cli.load_z_config()


def test_z_rank_dry_run_saves_nothing(tmp_path, capsys, cfg):
    """z-rank --dry-run: 割合を表示するだけで、保存先は変えない。"""
    import argparse

    from neochi import cli
    from neochi.store import JsonStore
    p = tmp_path / "s.json"
    s = JsonStore(p)
    s.upsert("show", {"id": "sh", "title": "t", "show_star": 4.8, "z_rank": "ZZZ", "listing_status": "listed"})
    s.upsert("episode", {"id": "e1", "show_id": "sh"})
    s.upsert("analysis", {"episode_id": "e1", "calm_star": 3.0, "interest_level": "mid", "interest_score": 5, "ear_star": 3.0,
                          "final_star": 4.8})
    s.save()
    before = p.read_text(encoding="utf-8")
    assert cli.cmd_z_rank(argparse.Namespace(store=str(p), rules_changed=True, dry_run=True)) == 0
    out = capsys.readouterr().out
    assert "ドライラン" in out and "ZZZ" in out and "格付けが変わる番組 1 件" in out
    assert p.read_text(encoding="utf-8") == before


def test_too_short_episodes_are_skipped():
    """入眠に必要な時間を確保できない短い回は解析しない。再生時間が不明な回は対象にする。"""
    from types import SimpleNamespace as NS
    from neochi import cli
    cfg = {"episode": {"min_minutes": 10}}
    assert cli._too_short(NS(duration_sec=4 * 60), cfg)
    assert cli._too_short(NS(duration_sec=599), cfg)
    assert not cli._too_short(NS(duration_sec=600), cfg)
    assert not cli._too_short(NS(duration_sec=None), cfg)
    assert not cli._too_short(NS(duration_sec=60), {})                      # 設定が無ければ何も除かない
    assert not cli._too_short(NS(duration_sec=60), {"episode": {"min_minutes": 0}})  # 0 = 無効
