"""文字起こし(faster-whisper)。冒頭 front_min 分(+ mid_min > 0 なら中盤のランダム区間)。"""
from __future__ import annotations

import random

from .features import decode_pcm

_model = None


def plan_segments(duration_sec: float, cfg: dict, rng: random.Random | None = None) -> list[tuple[float, float]]:
    """(開始秒, 長さ秒) のリスト。短い回は全体を1区間にする。"""
    t = cfg["transcribe"]
    front, mid = t["front_min"] * 60, t["mid_min"] * 60
    if duration_sec <= front + mid:
        return [(0.0, duration_sec)]
    if mid <= 0:
        return [(0.0, float(front))]
    rng = rng or random.Random()
    lo, hi = front, duration_sec - mid
    start = rng.uniform(lo, hi) if hi > lo else lo
    return [(0.0, float(front)), (start, float(mid))]


def transcribe(path: str, duration_sec: float, lang: str, cfg: dict, rng: random.Random | None = None) -> tuple[str, float, list[tuple[float, float, str]]]:
    """(文字起こし全文, 文字起こしした分数, 発話区間[(開始秒, 終了秒, 文字)]) を返す。区間の秒は回の頭からの絶対時刻。"""
    global _model
    from faster_whisper import WhisperModel  # 遅延 import(重い)

    t = cfg["transcribe"]
    if _model is None:
        _model = WhisperModel(t["whisper_model"], compute_type=t["whisper_compute_type"])
    texts, total, spans = [], 0.0, []
    for start, dur in plan_segments(duration_sec, cfg, rng):
        audio = decode_pcm(path, sr=16000, start=start, dur=dur)
        segs = list(_model.transcribe(audio, language=lang, vad_filter=True)[0])
        spans += [(start + s.start, start + s.end, s.text) for s in segs]
        texts.append("".join(s.text for s in segs) if lang == "ja" else " ".join(s.text.strip() for s in segs))
        total += len(audio) / 16000 / 60
    return ("\n".join(texts), total, spans)
