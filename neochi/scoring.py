"""評点の算出。数値はすべて config/scoring.yaml から読む。"""
from __future__ import annotations

from . import strings


def is_judged(row: dict) -> bool:
    """起伏(🌊)と興味(🎯)の両方を判定済みか。番組の評点と格付けには、判定済みの回だけを使う。

    耳のゆるさ(🎧)だけの点は、重みを配り直すと高く出やすい(実データで平均 4.49、3軸そろうと 4.16)ので、
    番組の評点には入れない。回の総合評点(final_star)は内部に残す。"""
    return row.get("calm_star") is not None and (row.get("interest_score") is not None
                                                  or row.get("interest_level") is not None)


def _norm(v: float, best: float, worst: float) -> float:
    """best で 1、worst で 0 の線形変換(範囲外は丸める)。"""
    if best == worst:
        return 1.0
    return max(0.0, min(1.0, (v - worst) / (best - worst)))


def _rate_unit(rate: float, r: dict) -> float:
    """話す速さは台形: best_max 以下は満点、worst で 0。slow_floor があればそれ未満も減点(初期値は無し)。"""
    if r.get("slow_floor") is not None and rate < r["slow_floor"]:
        return _norm(rate, r["slow_floor"], 0)
    if rate <= r["best_max"]:
        return 1.0
    return _norm(rate, r["best_max"], r["worst"])


def _star(unit: float) -> float:
    return round(1 + 4 * unit, 1)


def _ear_units(features: dict, lang: str, cfg: dict) -> dict:
    e = cfg["ear"]
    parts = {}
    rate = features.get("speech_rate")
    if rate is not None:
        r = e["rate"]["ja" if lang == "ja" else "en"]
        parts["rate"] = _rate_unit(rate, r)
    if features.get("speech_rate_cv") is not None:
        c = e["rate_cv"]
        parts["rate_cv"] = _norm(features["speech_rate_cv"], c["best"], c["worst"])
    if features.get("volume_std_db") is not None:
        v = e["volume_std_db"]
        parts["volume"] = _norm(features["volume_std_db"], v["best"], v["worst"])
    if features.get("sudden_per_10min") is not None:
        s = e["sudden_per_10min"]
        parts["sudden"] = _norm(features["sudden_per_10min"], s["best"], s["worst"])
    return parts


def ear_parts(features: dict, lang: str, cfg: dict) -> dict:
    """🎧 の内訳。項目ごとの★(1〜5)。アプリで「どこが効いているか」を見せるために保存する。"""
    return {k: _star(u) for k, u in _ear_units(features, lang, cfg).items()}


def ear_star(features: dict, lang: str, cfg: dict) -> float | None:
    """🎧 耳のゆるさ。取れた指標だけで重みを再配分する。全部欠けたら None。"""
    parts = _ear_units(features, lang, cfg)
    if not parts:
        return None
    w = {k: cfg["ear"]["weights"][k] for k in parts}
    return _star(sum(parts[k] * w[k] for k in parts) / sum(w.values()))


def calm_star(items_sum: float, cfg: dict) -> float:
    """🌊★。起伏の項目(0〜2点 × 4)の合計から、5 − 合計 × calm_slope(下限 1.0)。"""
    return max(1.0, round(5 - cfg["total"]["calm_slope"] * items_sum, 1))


def interest_star(score: float, cfg: dict) -> float:
    """🎯★。引き込み力(1〜10)がゾーンに入れば満点、外れるほど下がる(左右で下がり方が違う)。"""
    z = cfg["total"]["interest_zone"]
    lo, hi = z["zone"]
    if lo <= score <= hi:
        return 5.0
    if score < lo:
        x0, y0 = z["low_end"]
        return round(y0 + (5.0 - y0) * (score - x0) / (lo - x0), 1)
    x1, y1 = z["high_end"]
    return round(5.0 + (y1 - 5.0) * (score - hi) / (x1 - hi), 1)


def interest_rating_from_vote(vote: int, cfg: dict) -> int:
    """旧形式の3択(`interest_vote` -1 / 0 / 1)→ 10段階(1〜10)。10段階の導入前の行を、同じ★のまま引き継ぐ。"""
    return int(cfg["final"]["interest_vote_legacy_rating"][vote])


def blend_axis(ai: float | None, crowd: float | None, n: int, cfg: dict) -> float | None:
    """1つの軸(🌊 か 🎯)のAI解析の点に、みんなの評価を件数に応じて足す。10件未満は入れない。

    w = min(上限, n / (n + prior_n))。みんなの評価は、話の内容を見る軸(🌊🎯)にだけ効かせる。
    """
    f = cfg["final"]
    if ai is None or crowd is None or n < f["community_min_n"]:
        return ai
    w = min(f["community_max_weight"], n / (n + f["community_prior_n"]))
    return ai * (1 - w) + crowd * w


def total_star(calm: float | None, ear: float | None, interest_level: str | None, cfg: dict,
               interest_score: float | None = None,
               calm_votes: list[int] | None = None, interest_votes: list[int] | None = None) -> float | None:
    """😴 総合の元になる点(🎯🌊🎧)。欠けた要素は除いて重みを再配分する。

    calm_votes(1〜5) / interest_votes(🎯 引き込み力の10段階 1〜10)を渡すと、その軸にみんなの評価を足してから重み付けする(🎧には足さない)。
    渡さなければ、AI解析だけの点(`analysis.total_star`)。
    """
    t = cfg["total"]
    vals = {}
    if interest_score is not None:
        vals["interest"] = interest_star(interest_score, cfg)
    elif interest_level in t["interest_star"]:  # 旧形式(3段階だけ)の判定
        vals["interest"] = float(t["interest_star"][interest_level])
    if calm is not None:
        vals["calm"] = float(calm)
    if ear is not None:
        vals["ear"] = float(ear)
    if not vals:
        return None
    if calm_votes and "calm" in vals:
        vals["calm"] = blend_axis(vals["calm"], sum(calm_votes) / len(calm_votes), len(calm_votes), cfg)
    if interest_votes and "interest" in vals:
        stars = [interest_star(v, cfg) for v in interest_votes]  # みんなの10段階も、AIと同じゾーンの式に通す
        vals["interest"] = blend_axis(vals["interest"], sum(stars) / len(stars), len(stars), cfg)
    w = {k: t["weights"][k] for k in vals}
    return round(sum(vals[k] * w[k] for k in vals) / sum(w.values()), 1)


def watch_star(median_min: float, cfg: dict) -> float:
    """実測の分数の中央値 → 1〜5(短いほど高い。best 以下で 5.0、worst 以上で 1.0、その間は直線)。"""
    f = cfg["final"]
    return round(1 + 4 * _norm(median_min, f["watch_best_min"], f["watch_worst_min"]), 1)


def final_star(total: float | None, cfg: dict,
               watch_median: float | None = None, watch_n: int = 0,
               ai_total: float | None = None) -> tuple[float | None, str | None]:
    """総合評点と final_reason。人の手では上書きしない。

    total は、みんなの評価を軸ごとに足したあとの点(`total_star(..., calm_votes, interest_votes)`)。
    それに、ヘルスケアの実測を足す: 総合評点 = total×(1−w実測) + 実測点×w実測
    w実測 = min(上限, n / (n + prior_n))。3件(watch_min_n)未満は計算に入れない。
    ai_total(AI解析だけの点)があれば、実測とのずれが大きいときの理由に使う。
    """
    if total is None:
        return None, None
    f = cfg["final"]
    if watch_median is None or watch_n < f["watch_min_n"]:
        return total, None
    w = min(f["watch_max_weight"], watch_n / (watch_n + f["watch_prior_n"]))
    wstar = watch_star(watch_median, cfg)
    final = round(total * (1 - w) + wstar * w, 1)
    base = ai_total if ai_total is not None else total
    reason = (strings.divergence_reason(base, wstar, "実測", watch_n)
              if abs(base - wstar) >= f["divergence_threshold"] else None)
    return final, reason
