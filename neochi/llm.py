"""Claude で 🌊 と 🎯 を判定する。採点基準表と文字起こしを渡し、根拠1行をJSONで返させる。"""
from __future__ import annotations

import json
import re
from pathlib import Path

RUBRIC = Path(__file__).resolve().parent.parent / "config" / "rubric.md"
LEVELS = {"low", "mid", "high"}


def build_prompt(title: str, show_title: str, text: str, cfg: dict) -> str:
    body = text[: cfg["llm"]["max_chars"]]
    return (
        f"{RUBRIC.read_text(encoding='utf-8')}\n\n"
        f"## 対象\n番組: {show_title}\n回: {title}\n\n## 文字起こし(一部)\n{body}\n"
    )


INTEREST_ITEMS = ("A", "B", "C", "D", "E")   # 🎯 引き込み力の項目(config/rubric.md)
CALM_ITEMS = ("A", "B", "C", "D")            # 🌊 起伏の項目


def _items(d: dict, keys: tuple[str, ...], name: str) -> dict:
    if not isinstance(d, dict):
        raise ValueError(f"{name} がありません")
    out = {}
    for k in keys:
        v = d.get(k)
        score = v.get("score") if isinstance(v, dict) else v
        if score not in (0, 1, 2):
            raise ValueError(f"{name}.{k} は 0/1/2: {v}")
        out[k] = {"score": score, "min": v.get("min") if isinstance(v, dict) else None}
    return out


def level_of(score: int) -> str:
    """引き込み力(1〜10)から3段階を決める。表示とユーザーの3択との比較用。"""
    return "low" if score <= 3 else "mid" if score <= 6 else "high"


def parse_judgement(raw: str) -> dict:
    """応答からJSONを取り出して検証する。不正なら ValueError。

    新形式: {"interest": {A..E: 0/1/2 または {"score", "min"}}, "calm": {A..D: 同}, "moments": [...], "reason": "..."}
      → 引き込み力 = 合計(0のとき1)、🌊★ = 5 − 合計×0.5 をコードで計算する(AIに★を直接付けさせない)。
    旧形式: {"calm_star", "interest_level", "reason"} も受ける。
    """
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise ValueError("JSON が見つかりません")
    d = json.loads(m.group(0))
    reason = str(d.get("reason", "")).strip()
    if "interest" in d or "calm" in d:
        ii = _items(d.get("interest"), INTEREST_ITEMS, "interest")
        cc = _items(d.get("calm"), CALM_ITEMS, "calm")
        score = max(1, sum(v["score"] for v in ii.values()))
        calm = 5 - 0.5 * sum(v["score"] for v in cc.values())
        moments = []
        for x in (d.get("moments") or [])[:3]:
            if isinstance(x, dict) and isinstance(x.get("min"), (int, float)) and str(x.get("note", "")).strip():
                moments.append({"min": int(x["min"]), "note": str(x["note"]).strip()[:60]})
        return {"calm_star": calm, "interest_level": level_of(score), "interest_score": score, "reason": reason,
                "items": {"interest": ii, "calm": cc}, "moments": moments}
    calm = float(d["calm_star"])
    level = d["interest_level"]
    if not 1 <= calm <= 5 or level not in LEVELS:
        raise ValueError(f"範囲外の値: {d}")
    return {"calm_star": round(calm * 2) / 2, "interest_level": level, "interest_score": None, "reason": reason,
            "items": None, "moments": []}


def judge(title: str, show_title: str, text: str, cfg: dict, client=None) -> dict:
    if client is None:
        import anthropic  # 遅延 import

        client = anthropic.Anthropic()
    msg = client.messages.create(
        model=cfg["llm"]["model"],
        max_tokens=cfg["llm"]["max_tokens"],
        messages=[{"role": "user", "content": build_prompt(title, show_title, text, cfg)}],
    )
    return parse_judgement("".join(b.text for b in msg.content if getattr(b, "type", "") == "text"))
