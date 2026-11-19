"""観察(config/rubric_v2.md)の検証と、点の計算。AIには点を書かせない。数値は config/observe.yaml(仮)。

まだ本番の採点には使わない。確かめ用の回で点の出方を確かめてから、pipeline に繋ぐ。
"""
from __future__ import annotations

import json
import re

import yaml

from . import llm

KINDS = ("negative", "conflict", "excitement")
TOPICS = ("health", "money", "work", "incident", "future", "other")
QUOTE_MAX = 40


def load_config() -> dict:
    from .versions import ROOT
    return yaml.safe_load((ROOT / "config" / "observe.yaml").read_text(encoding="utf-8"))


def _quote(v) -> str | None:
    q = str(v or "").strip()
    return q[:QUOTE_MAX] if q else None   # 引用がない観察は数えない


def _minute(v, minutes: int) -> int | None:
    return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v < minutes else None


def _span(x: dict, minutes: int) -> tuple[int, int] | None:
    a = _minute(x.get("from", x.get("min")), minutes)
    b = _minute(x.get("to", x.get("from", x.get("min"))), minutes)
    if a is None or b is None or b < a:
        return None
    return a, b


def parse_observations(raw: str, cfg: dict | None = None) -> dict:
    """応答の JSON を検証して、数えられる観察だけを残す。JSON がなければ ValueError。
    分が範囲外、種類が不明、引用がない観察は、捨てる(捨てた件数は dropped に残す)。"""
    cfg = cfg or load_config()
    minutes = cfg["minutes"]
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise ValueError("JSON が見つかりません")
    d = json.loads(m.group(0))
    dropped = 0
    emotion, worry, hook, follow, imagery, load = [], [], [], [], [], []
    for x in d.get("emotion") or []:
        mi, q = _minute(x.get("min"), minutes), _quote(x.get("quote"))
        if mi is None or q is None or x.get("kind") not in KINDS or x.get("strength") not in (1, 2):
            dropped += 1
            continue
        emotion.append({"min": mi, "kind": x["kind"], "strength": x["strength"], "quote": q})
    for x in d.get("worry") or []:
        mi, q = _minute(x.get("min"), minutes), _quote(x.get("quote"))
        if mi is None or q is None:
            dropped += 1
            continue
        worry.append({"min": mi, "topic": x.get("topic") if x.get("topic") in TOPICS else "other", "quote": q})
    for x in d.get("hook") or []:
        mi, q = _minute(x.get("min"), minutes), _quote(x.get("quote"))
        if mi is None or q is None:
            dropped += 1
            continue
        hook.append({"min": mi, "quote": q})
    for name, dst in (("follow", follow), ("imagery", imagery), ("load", load)):
        for x in d.get(name) or []:
            sp, q = _span(x, minutes), _quote(x.get("quote"))
            if sp is None or q is None:
                dropped += 1
                continue
            dst.append({"from": sp[0], "to": sp[1], "quote": q})
    return {"emotion": emotion, "worry": worry, "hook": hook, "follow": follow, "imagery": imagery, "load": load, "dropped": dropped,
            "reason": str(d.get("reason", "")).strip(), "content_summary": llm.content_summary(d.get("content_summary")),
            "content_start": llm.content_start(d.get("content_start"))}


def _fw(minute: int, cfg: dict) -> float:
    f = cfg["front_weight"]
    return 1.0 if minute < f["from_min"] else f["weight"]


def _event_weights(obs: dict, cfg: dict) -> list[float]:
    """1分ごとの、感情と心配の観察の重みの合計(前半の重みは付けない)。"""
    e = cfg["emotion"]
    w = [0.0] * cfg["minutes"]
    for x in obs["emotion"]:
        w[x["min"]] += e["kind_weight"][x["kind"]] * e["strength_weight"][x["strength"]]
    for x in obs["worry"]:
        w[x["min"]] += cfg["worry_weight"]
    return w


def calm_per_min(obs: dict, cfg: dict) -> list[float]:
    """1分ごとの起伏(0〜cap)。観察から作る(AIが別に書かないので、観察と食い違わない)。"""
    p = cfg["calm"]["per_min"]
    return [round(min(p["cap"], v * p["event_weight"]), 1) for v in _event_weights(obs, cfg)]


def _coverage(spans: list[dict], cfg: dict) -> float:
    covered = set()
    for s in spans:
        covered.update(range(s["from"], s["to"] + 1))
    return len(covered) / cfg["minutes"]


def load_points(obs: dict, cfg: dict) -> float:
    """頭の負荷の点(0〜max_points)。頭の負荷が高い区間が、冒頭のうち cov_full を占めたら満点(= 最大の加点)。"""
    l = cfg["load"]
    return min(1.0, _coverage(obs["load"], cfg) / l["cov_full"]) * l["max_points"]


def calm_raw(obs: dict, cfg: dict) -> float:
    """起伏の合計(小さいほど穏やか)= 感情・心配の重み(前半を重く)+ 頭の負荷の点。"""
    ev = sum(v * _fw(i, cfg) for i, v in enumerate(_event_weights(obs, cfg)))
    return ev + load_points(obs, cfg)


def calm_star(obs: dict, cfg: dict) -> float:
    return max(1.0, round(5 - cfg["calm"]["slope"] * calm_raw(obs, cfg), 1))


def interest_star(obs: dict, cfg: dict) -> float:
    """🎯★ = 5 − 引き込まれすぎの減点(先が気になる・追い続ける必要)− 退屈の減点(思い浮かぶ具体性が少ない)。下限 1.0。"""
    i = cfg["interest"]
    hooks = min(i["hook_max"], sum(i["hook_penalty"] * _fw(x["min"], cfg) for x in obs["hook"]))
    follow = i["follow_penalty"] * _coverage(obs["follow"], cfg)
    b = i["boredom"]
    short = max(0.0, b["coverage_ok"] - _coverage(obs["imagery"], cfg)) / b["coverage_ok"]
    return max(1.0, round(5 - hooks - follow - b["penalty"] * short, 1))
