"""1回分の解析 → 保存。外部依存は Deps に差し替え可能(テスト用)。"""
from __future__ import annotations

import logging
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from . import audio, feeds, features, llm, scoring, transcribe

log = logging.getLogger("neochi.pipeline")


@dataclass
class Deps:
    download: Callable = audio.downloaded
    decode: Callable = features.decode_pcm
    transcribe: Callable = transcribe.transcribe
    judge: Callable | None = llm.judge   # None = API を使わず、判定待ちとして書き出す(セッションで判定する)
    pending_dir: str = "work/pending"     # judge=None のときの書き出し先(文字起こしを含むのでリポジトリに入れない)


def analyze_episode(show: feeds.Show, ep: feeds.Episode, cfg: dict, store, deps: Deps | None = None) -> dict:
    """音声DL → 特徴量 → 文字起こし → LLM → ★ → upsert。音声は with を抜けると消える。"""
    deps = deps or Deps()
    feat: dict = {}
    text, minutes = "", 0.0
    input_depth = "meta"

    try:
        with deps.download(ep.audio_url) as path:
            sr = cfg["acoustic"]["sample_rate"]
            feat = features.acoustic_features(deps.decode(path, sr=sr), sr, cfg)
            input_depth = "audio"
            if feat["sudden_per_10min"] is not None and feat["sudden_per_10min"] > cfg["acoustic"]["warn_sudden_per_10min"]:
                log.warning("突発音が異常値です(%.0f回/10分): %s / %s", feat["sudden_per_10min"], show.title, ep.title)
            try:
                res = deps.transcribe(path, feat["duration_sec"], show.lang, cfg)
                text, minutes = res[0], res[1]
                spans = res[2] if len(res) > 2 else []
                if text.strip():
                    rate, unit = features.speech_rate(text, show.lang, minutes)
                    feat["speech_rate"], feat["speech_rate_unit"] = rate, unit
                    if spans:  # 前半に重みを付けた速さと、速さのばらつき
                        feat.update(features.rate_profile(spans, show.lang, cfg))
                        if "rate_per_min" in feat:
                            feat.setdefault("timeline", {})["rate_per_min"] = feat.pop("rate_per_min")
                    input_depth = "transcript"
            except Exception as e:  # noqa: BLE001 - 文字起こしの失敗は特徴量だけで続行
                log.warning("文字起こしに失敗(音響特徴量のみで続行): %s (%s)", ep.title, e)
    except Exception as e:  # noqa: BLE001
        log.warning("音声を扱えませんでした(メタ情報のみ): %s (%s)", ep.title, e)

    calm, level, reason = None, None, ""
    if input_depth == "transcript" and deps.judge is None:
        d = Path(deps.pending_dir)
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{_safe(ep.id)}.json").write_text(json.dumps({
            "episode_id": ep.id, "show": show.title, "title": ep.title, "transcript": text,
        }, ensure_ascii=False, indent=1), encoding="utf-8")
    elif input_depth == "transcript":
        try:
            j = deps.judge(ep.title, show.title, text, cfg)
            calm, level, reason = j["calm_star"], j["interest_level"], j["reason"]
        except Exception as e:  # noqa: BLE001
            log.warning("LLM 判定に失敗(🌊🎯は空): %s (%s)", ep.title, e)

    ear = scoring.ear_star(feat, show.lang, cfg)
    if ear is not None:
        feat["ear_parts"] = scoring.ear_parts(feat, show.lang, cfg)
    total, final, final_reason = _stars(calm, ear, level, ep.id, cfg, store)

    store.upsert("show", {"id": show.id, "title": show.title, "publisher": show.publisher,
                          "rss_url": show.rss_url, "genre": show.genre, "lang": show.lang,
                          "artwork_url": show.artwork_url, "link_url": show.link_url})
    store.upsert("episode", {"id": ep.id, "show_id": show.id, "title": ep.title, "audio_url": ep.audio_url,
                             "duration_sec": ep.duration_sec or (int(feat["duration_sec"]) if feat.get("duration_sec") else None),
                             "published_at": ep.published_at, "link_url": ep.link_url})
    row = {
        "episode_id": ep.id, "input_depth": input_depth, "interest_level": level,
        "calm_star": calm, "ear_star": ear, "total_star": total,
        "final_star": final, "final_reason": final_reason,
        "reasons": {"llm": reason} if reason else {},
        "features": {k: v for k, v in feat.items() if v is not None},
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
    }
    store.upsert("analysis", row)
    return row


def _safe(eid: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in eid)[:120]


def _stars(calm, ear, level, episode_id: str, cfg: dict, store):
    total = scoring.total_star(calm, ear, level, cfg)
    crowd, n = store.community(episode_id)
    final, final_reason = scoring.final_star(total, crowd, n, cfg)
    return total, final, final_reason


def apply_judgement(j: dict, cfg: dict, store) -> dict:
    """セッションで判定した🌊🎯を、保存済みの解析に入れて★を計算し直す。

    j = {"episode_id", "calm_star", "interest_level", "reason"}。値の検証は llm.parse_judgement と同じ。
    """
    v = llm.parse_judgement(json.dumps(j, ensure_ascii=False))
    row = store.get("analysis", j["episode_id"])
    if row is None:
        raise KeyError(f"解析が見つかりません: {j['episode_id']}")
    total, final, final_reason = _stars(v["calm_star"], row.get("ear_star"), v["interest_level"], j["episode_id"], cfg, store)
    new = {**row, "calm_star": v["calm_star"], "interest_level": v["interest_level"],
           "total_star": total, "final_star": final, "final_reason": final_reason,
           "reasons": {**(row.get("reasons") or {}), "llm": v["reason"]}}
    store.upsert("analysis", new)
    return new
