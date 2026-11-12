"""音響特徴量と話す速さ。"""
from __future__ import annotations

import re
import subprocess

import numpy as np


def decode_pcm(path: str, sr: int = 8000, start: float | None = None, dur: float | None = None) -> np.ndarray:
    """ffmpeg でモノラルのfloat32(-1〜1)にする。start/dur は秒。"""
    cmd = ["ffmpeg", "-v", "error"]
    if start is not None:
        cmd += ["-ss", f"{start:.2f}"]
    if dur is not None:
        cmd += ["-t", f"{dur:.2f}"]
    cmd += ["-i", path, "-ac", "1", "-ar", str(sr), "-f", "s16le", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.int16).astype(np.float32) / 32768.0


def frame_db(x: np.ndarray, sr: int, frame_sec: float = 1.0) -> np.ndarray:
    """フレームごとの RMS(dBFS)。"""
    n = int(sr * frame_sec)
    if n <= 0 or len(x) < n:
        return np.array([], dtype=np.float32)
    frames = x[: len(x) // n * n].reshape(-1, n)
    rms = np.sqrt((frames ** 2).mean(axis=1))
    return 20 * np.log10(np.maximum(rms, 1e-8))


def acoustic_features(x: np.ndarray, sr: int, cfg: dict) -> dict:
    """duration_sec / volume_std_db / sudden_per_10min。

    突発音: 中央値より +10dB 超、かつ直前のフレームから +6dB 超のフレームを1回と数える。
    """
    a = cfg["acoustic"]
    db = frame_db(x, sr, a["frame_sec"])
    duration = len(x) / sr
    active = db[db > a["silence_floor_db"]]
    if len(active) == 0:
        return {"duration_sec": duration, "volume_std_db": None, "sudden_per_10min": None}
    median = float(np.median(active))
    sudden = 0
    for i in range(1, len(db)):
        if db[i] > a["silence_floor_db"] and db[i] > median + a["sudden_over_median_db"] \
                and db[i] - db[i - 1] > a["sudden_over_prev_db"]:
            sudden += 1
    minutes = max(duration / 60, 1e-9)
    return {
        "duration_sec": duration,
        "volume_std_db": float(active.std()),
        "sudden_per_10min": sudden / minutes * 10,
    }


_JA_JUNK = re.compile(r"[\s、。，．,.!?！？「」『』（）()\-ー…・]")


def speech_rate(text: str, lang: str, minutes: float) -> tuple[float | None, str]:
    """日本語は 字/分、英語は 語/分。単位も返す(言語間で直接比較しない)。"""
    if minutes <= 0 or not text.strip():
        return None, "chars_per_min" if lang == "ja" else "words_per_min"
    if lang == "ja":
        return len(_JA_JUNK.sub("", text)) / minutes, "chars_per_min"
    return len(text.split()) / minutes, "words_per_min"
