"""寝落ち格付け Z / ZZ / ZZZ。番組の評点(総合評点の平均)だけで決める。基準未満は None(掲載しない)。"""
from __future__ import annotations

def z_rank(show_star: float | None, cfg: dict) -> str | None:
    """評点から格付けを返す。評点が基準を下回ったら、すぐ下げる(格下げの保留はしない。2026-11-16)。

    評点がない(起伏・興味の判定が済んだ回がない)ときは None。まだ判定していないため、格付けも付けない。"""
    if show_star is None:
        return None
    for name, key in (("ZZZ", "zzz"), ("ZZ", "zz"), ("Z", "z")):
        if show_star >= cfg[key]["min_star"]:
            return name
    return None
