"""掲載ランク Z / ZZ / ZZZ。実測(source=watch)の入眠までの分数だけで決める。"""
from __future__ import annotations


def z_rank(latencies_min: list[float], cfg: dict) -> str | None:
    """実測がなければ None(調査中)。条件を満たす最も高いランクを返す。"""
    if not latencies_min:
        return None
    line = cfg["threshold_min"]
    n = len(latencies_min)
    under = sum(1 for m in latencies_min if m < line)
    ratio = under / n

    def ok(rule: dict) -> bool:
        if under < 1 or n < rule["min_count"]:
            return False
        return rule.get("min_ratio") is None or ratio >= rule["min_ratio"]

    for name, key in (("ZZZ", "zzz"), ("ZZ", "zz"), ("Z", "z")):
        if ok(cfg[key]):
            return name
    return None
