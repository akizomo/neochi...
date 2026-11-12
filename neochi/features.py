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


def _count(text: str, lang: str) -> int:
    return len(_JA_JUNK.sub("", text)) if lang == "ja" else len(text.split())


def rate_profile(spans: list[tuple[float, float, str]], lang: str, cfg: dict) -> dict:
    """前半に重みを付けた話す速さと、速さのばらつき(1分ごとの変動係数)。

    spans は (開始秒, 終了秒, 文字)。速さは発話していた時間で割る(無音を除く)。
    重み: front_weight.window_min 分ごとに weights を順に当て、それより後(中盤)は mid_weight。
    """
    fw = cfg["front_weight"]
    win = fw["window_min"] * 60
    front_end = win * len(fw["weights"])

    def weight(t: float) -> float:
        return fw["weights"][int(t // win)] if t < front_end else fw["mid_weight"]

    num = den = 0.0
    per_min: dict[int, list[float]] = {}
    for a, b, text in spans:
        dur = b - a
        if dur <= 0:
            continue
        n = _count(text, lang)
        w = weight(a)
        num += w * n
        den += w * dur / 60
        m = per_min.setdefault(int(a // 60), [0.0, 0.0])
        m[0] += n
        m[1] += dur / 60
    out: dict = {}
    if den > 0:
        out["speech_rate"] = num / den
    rates = [c / d for c, d in per_min.values() if d >= 0.25]
    if len(rates) >= 3:
        arr = np.array(rates)
        if arr.mean() > 0:
            out["speech_rate_cv"] = float(arr.std() / arr.mean())
    return out
