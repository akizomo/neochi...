"""解析の版。どの定義で作った行かを記録し、定義を変えたときに、やり直す行(古い版)を見つける。

transcript = 文字起こしのやり方(モデル・範囲)。rubric = 採点基準(config/rubric.md)。scoring = 点の計算(config/scoring.yaml)。
中身のハッシュなので、定義を直せば、版は自動で変わる(版の番号を手で上げ忘れない)。
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _hash(path: Path) -> str:
    try:
        return hashlib.sha1(path.read_bytes()).hexdigest()[:8]
    except OSError:
        return "unknown"


def transcript_version(cfg: dict) -> str:
    t = cfg["transcribe"]
    return f"{t['whisper_model']}/{t['whisper_compute_type']}/front{t['front_min']}/mid{t['mid_min']}"


def current(cfg: dict) -> dict:
    return {"transcript": transcript_version(cfg),
            "rubric": _hash(ROOT / "config" / "rubric.md"),
            "scoring": _hash(ROOT / "config" / "scoring.yaml")}


def stale(row_versions: dict | None, kinds: tuple[str, ...], cfg: dict) -> bool:
    """行の版が、いまの定義と違う(または記録がない)なら True。kinds は見る版の種類。"""
    now, got = current(cfg), row_versions or {}
    return any(got.get(k) != now[k] for k in kinds)
