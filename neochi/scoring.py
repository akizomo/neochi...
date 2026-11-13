"""★の算出。数値はすべて config/scoring.yaml から読む。"""
from __future__ import annotations

from . import strings


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


def total_star(calm: float | None, ear: float | None, interest_level: str | None, cfg: dict,
               interest_score: float | None = None) -> float | None:
    """😴 AI解析の総合。欠けた要素は除いて重みを再配分する。"""
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
    w = {k: t["weights"][k] for k in vals}
    return round(sum(vals[k] * w[k] for k in vals) / sum(w.values()), 1)


def final_star(total: float | None, community: float | None, community_n: int, cfg: dict) -> tuple[float | None, str | None]:
    """最終★と final_reason。みんなが0件の間は AI解析のみ。人の手では上書きしない。"""
    if total is None:
        return None, None
    if not community_n or community is None:
        return total, None
    f = cfg["final"]
    w = min(f["community_max_weight"], community_n / (community_n + f["community_prior_n"]))
    final = round(total * (1 - w) + community * w, 1)
    reason = None
    if abs(total - community) >= f["divergence_threshold"]:
        reason = strings.divergence_reason(total, community, community_n)
    return final, reason
