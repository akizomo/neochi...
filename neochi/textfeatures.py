"""文字起こしから、機械で数える特徴。AIの判定に頼らない(🎧と同じく、誰が何度測っても同じ値)。数値や基準は仮。"""
from __future__ import annotations

import re

_NUM = re.compile(r"[0-9０-９]+(?:[.,．，][0-9０-９]+)*")
_KATAKANA = re.compile(r"[ァ-ヴー]{4,}")          # 4字以上のカタカナ語(固有名詞・専門用語・外来語の目安)
_ALPHA = re.compile(r"[A-Za-zＡ-Ｚａ-ｚ]{2,}")      # 英字2字以上(略語・固有名詞の目安)
_JUNK = re.compile(r"[\s、。，．,.!?！？「」『』（）()\-…・]")


def load_density(text: str) -> float | None:
    """頭の負荷の目安: 数字・カタカナ語・英字語の、1000字あたりの数。字がなければ None。"""
    n = len(_JUNK.sub("", text))
    if n == 0:
        return None
    count = len(_NUM.findall(text)) + len(_KATAKANA.findall(text)) + len(_ALPHA.findall(text))
    return count * 1000 / n


def novelty_per_min(spans: list[tuple[float, float, str]], minutes: int = 20) -> list[float | None]:
    """1分ごとの、新しい言い回しの割合(それまでの分に出ていない、2字の並びの割合)。同じ話の繰り返しが続くと下がる。
    記録だけして、点にはまだ使わない(基準は、実データを見て決める)。"""
    per: dict[int, list[str]] = {}
    for a, _b, t in spans:
        m = int(a // 60)
        if m < minutes:
            per.setdefault(m, []).append(_JUNK.sub("", t))
    seen: set[str] = set()
    out: list[float | None] = []
    for m in range(minutes):
        s = "".join(per.get(m, []))
        grams = [s[i:i + 2] for i in range(len(s) - 1)]
        if len(grams) < 20:
            out.append(None)
            continue
        out.append(round(sum(g not in seen for g in grams) / len(grams), 2))
        seen.update(grams)
    return out
