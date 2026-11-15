"""寝落ち格付け Z / ZZ / ZZZ。番組の評点(総合評点の平均)だけで決める。基準未満は None(掲載しない)。"""
from __future__ import annotations

_ORDER = {None: 0, "Z": 1, "ZZ": 2, "ZZZ": 3}


def z_rank(show_star: float | None, cfg: dict, current: str | None = None, watch_n: int = 0) -> str | None:
    """評点から格付けを返す。すでに付いた格付けは、実測が demote_min_watch 件以上になるまで下げない。"""
    rank = None
    if show_star is not None:
        for name, key in (("ZZZ", "zzz"), ("ZZ", "zz"), ("Z", "z")):
            if show_star >= cfg[key]["min_star"]:
                rank = name
                break
    if _ORDER[rank] < _ORDER.get(current, 0) and watch_n < cfg["demote_min_watch"]:
        return current
    return rank
