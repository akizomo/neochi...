"""★の算出。数値はすべて config/scoring.yaml から読む。"""
from __future__ import annotations

from . import strings


def _norm(v: float, best: float, worst: float) -> float:
    """best で 1、worst で 0 の線形変換(範囲外は丸める)。"""
    if best == worst:
        return 1.0
    return max(0.0, min(1.0, (v - worst) / (best - worst)))


def _star(unit: float) -> float:
    return round(1 + 4 * unit, 1)


def ear_star(features: dict, lang: str, cfg: dict) -> float | None:
    """🎧 耳のゆるさ。取れた指標だけで重みを再配分する。全部欠けたら None。"""
    e = cfg["ear"]
    parts = {}
    rate = features.get("speech_rate")
    if rate is not None:
        r = e["rate"]["ja" if lang == "ja" else "en"]
        parts["rate"] = _norm(rate, r["best"], r["worst"])
    if features.get("volume_std_db") is not None:
        v = e["volume_std_db"]
        parts["volume"] = _norm(features["volume_std_db"], v["best"], v["worst"])
    if features.get("sudden_per_10min") is not None:
        s = e["sudden_per_10min"]
        parts["sudden"] = _norm(features["sudden_per_10min"], s["best"], s["worst"])
    if not parts:
        return None
    w = {k: e["weights"][k] for k in parts}
    return _star(sum(parts[k] * w[k] for k in parts) / sum(w.values()))


def total_star(calm: float | None, ear: float | None, interest_level: str | None, cfg: dict) -> float | None:
    """😴 AI解析の総合。欠けた要素は除いて重みを再配分する。"""
    t = cfg["total"]
    vals = {}
    if interest_level in t["interest_star"]:
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
