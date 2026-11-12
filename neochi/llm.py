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


def parse_judgement(raw: str) -> dict:
    """応答からJSONを取り出して検証する。不正なら ValueError。"""
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise ValueError("JSON が見つかりません")
    d = json.loads(m.group(0))
    calm = float(d["calm_star"])
    level = d["interest_level"]
    if not 1 <= calm <= 5 or level not in LEVELS:
        raise ValueError(f"範囲外の値: {d}")
    return {"calm_star": round(calm * 2) / 2, "interest_level": level, "reason": str(d.get("reason", "")).strip()}


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
