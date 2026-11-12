"""1回分の解析 → 保存。外部依存は Deps に差し替え可能(テスト用)。"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable

from . import audio, feeds, features, llm, scoring, transcribe

log = logging.getLogger("neochi.pipeline")


@dataclass
class Deps:
    download: Callable = audio.downloaded
    decode: Callable = features.decode_pcm
    transcribe: Callable = transcribe.transcribe
    judge: Callable = llm.judge


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
                    input_depth = "transcript"
            except Exception as e:  # noqa: BLE001 - 文字起こしの失敗は特徴量だけで続行
                log.warning("文字起こしに失敗(音響特徴量のみで続行): %s (%s)", ep.title, e)
    except Exception as e:  # noqa: BLE001
        log.warning("音声を扱えませんでした(メタ情報のみ): %s (%s)", ep.title, e)

    calm, level, reason = None, None, ""
    if input_depth == "transcript":
        try:
            j = deps.judge(ep.title, show.title, text, cfg)
            calm, level, reason = j["calm_star"], j["interest_level"], j["reason"]
        except Exception as e:  # noqa: BLE001
            log.warning("LLM 判定に失敗(🌊🎯は空): %s (%s)", ep.title, e)

    ear = scoring.ear_star(feat, show.lang, cfg)
    total = scoring.total_star(calm, ear, level, cfg)
    crowd, n = store.community(ep.id)
    final, final_reason = scoring.final_star(total, crowd, n, cfg)

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
