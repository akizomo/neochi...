"""1回分の解析 → 保存。外部依存は Deps に差し替え可能(テスト用)。"""
from __future__ import annotations

import logging
import json
import statistics
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
    text, minutes, spans = "", 0.0, []
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

    calm, level, reason, j = None, None, "", None
    if input_depth == "transcript" and deps.judge is None:
        d = Path(deps.pending_dir)
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{_safe(ep.id)}.json").write_text(json.dumps({
            "episode_id": ep.id, "show": show.title, "title": ep.title,
            "transcript": with_minute_marks(spans) if spans else text,
            "opening": with_second_marks(spans) if spans else "",   # 本編の開始を秒で答えるための、冒頭5分
        }, ensure_ascii=False, indent=1), encoding="utf-8")
    elif input_depth == "transcript":
        try:
            j = deps.judge(ep.title, show.title, text, cfg)
            calm, level, reason = j["calm_star"], j["interest_level"], j["reason"]
        except Exception as e:  # noqa: BLE001
            j = None
            log.warning("LLM 判定に失敗(🌊🎯は空): %s (%s)", ep.title, e)

    ear = scoring.ear_star(feat, show.lang, cfg)
    if ear is not None:
        feat["ear_parts"] = scoring.ear_parts(feat, show.lang, cfg)
    interest_score = j.get("interest_score") if j else None
    total, final, final_reason = _stars(calm, ear, level, ep.id, cfg, store, interest_score)

    store.upsert("show", {"id": show.id, "title": show.title, "publisher": show.publisher,
                          "rss_url": show.rss_url, "genre": show.genre, "cohort": show.cohort, "apple_category": show.apple_category, "lang": show.lang,
                          "artwork_url": show.artwork_url, "link_url": show.link_url})
    store.upsert("episode", {"id": ep.id, "show_id": show.id, "title": ep.title, "audio_url": ep.audio_url,
                             "duration_sec": ep.duration_sec or (int(feat["duration_sec"]) if feat.get("duration_sec") else None),
                             "published_at": ep.published_at, "link_url": ep.link_url})
    row = {
        "episode_id": ep.id, "input_depth": input_depth, "interest_level": level,
        "calm_star": calm, "ear_star": ear, "total_star": total,
        "final_star": final, "final_reason": final_reason,
        "reasons": _reasons({}, j) if j else ({"llm": reason} if reason else {}),
        "features": {k: v for k, v in feat.items() if v is not None},
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
    }
    if interest_score is not None:
        row["interest_score"] = interest_score
    row.update(_new_outputs(j))
    store.upsert("analysis", row)
    return row


def _reasons(base: dict, v: dict) -> dict:
    """判定の結果を reasons に入れる(根拠の一行・項目ごとの点・起伏の山)。"""
    out = {**base}
    if v.get("reason"):
        out["llm"] = v["reason"]
    if v.get("items"):
        out["items"] = v["items"]
    out["moments"] = v.get("moments") or []
    return out


def _new_outputs(v: dict | None) -> dict:
    """1分ごとの起伏と内容の要約(列)。無いときは書かない(古い回は null のまま、画面はその図と箱を出さない)。"""
    if not v:
        return {}
    out = {k: v[k] for k in ("calm_per_min", "content_summary") if v.get(k) is not None}
    cs = v.get("content_start")
    if cs:  # 本編の開始(秒と、最初の一言)。解析時の音声での位置。アプリは一言で位置を合わせ直す
        out["content_start_sec"], out["content_start_anchor"] = cs["sec"], cs["anchor"]
    return out


def with_minute_marks(spans) -> str:
    """文字起こしに [n分] の目印を入れる(判定で、根拠の時刻を書けるようにする)。"""
    out, cur = [], -1
    for a, _b, t in spans:
        m = int(a // 60)
        if m != cur:
            out.append(f"\n[{m}分] ")
            cur = m
        out.append(t)
    return "".join(out).strip()


def with_second_marks(spans, until_sec: int = llm.CONTENT_START_MAX_SEC + 60) -> str:
    """冒頭の文字起こしに、[m:ss] の目印を行ごとに入れる(本編が始まる秒を、判定で答えられるように)。"""
    lines = []
    for a, _b, t in spans:
        if a > until_sec:
            break
        lines.append(f"[{int(a // 60)}:{int(a % 60):02d}] {t.strip()}")
    return "\n".join(lines)


def _safe(eid: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in eid)[:120]


def _stars(calm, ear, level, episode_id: str, cfg: dict, store, interest_score=None):
    """(AI解析だけの点, 総合評点, final_reason)。総合評点 = みんなの評価を🌊🎯に足した点に、実測を足したもの。"""
    total = scoring.total_star(calm, ear, level, cfg, interest_score)
    calm_votes, interest_votes = store.votes(episode_id)
    with_crowd = scoring.total_star(calm, ear, level, cfg, interest_score, calm_votes, interest_votes)
    watch = store.episode_watch_latencies(episode_id)
    median = statistics.median(watch) if watch else None
    final, final_reason = scoring.final_star(with_crowd, cfg, median, len(watch), ai_total=total)
    return total, final, final_reason


def remeasure_acoustics(row: dict, audio_url: str, lang: str, cfg: dict, store, deps: Deps | None = None) -> dict:
    """保存済みの解析の、音響の特徴(音量のばらつき・突発音・推移)だけを測り直す。🌊🎯と話す速さは、そのまま。

    測る範囲や基準(acoustic.window_min、ear の基準)を変えたあとに使う。音声は、測ったら捨てる。
    🎧★と総合評点も計算し直して保存する。
    """
    deps = deps or Deps()
    sr = cfg["acoustic"]["sample_rate"]
    with deps.download(audio_url) as path:
        new = features.acoustic_features(deps.decode(path, sr=sr), sr, cfg)
    feat = dict(row.get("features") or {})
    timeline = dict(feat.get("timeline") or {})
    for k in ("duration_sec", "volume_std_db", "sudden_per_10min"):
        feat[k] = new.get(k)
    timeline.update(new.get("timeline") or {})
    feat["timeline"] = timeline
    feat = {k: v for k, v in feat.items() if v is not None}
    ear = scoring.ear_star(feat, lang, cfg)
    if ear is not None:
        feat["ear_parts"] = scoring.ear_parts(feat, lang, cfg)
    total, final, reason = _stars(row.get("calm_star"), ear, row.get("interest_level"), row["episode_id"], cfg, store,
                                  row.get("interest_score"))
    out = {**row, "features": feat, "ear_star": ear, "total_star": total, "final_star": final, "final_reason": reason}
    store.upsert("analysis", out)
    return out


def recalm(row: dict, cfg: dict) -> dict:
    """保存済みの項目の点から、🌊★を計算し直す(calm_slope を変えたとき)。項目がない古い解析は、そのまま。"""
    items = ((row.get("reasons") or {}).get("items") or {}).get("calm")
    if not items:
        return row
    return {**row, "calm_star": scoring.calm_star(sum(v["score"] for v in items.values()), cfg)}


def reear(row: dict, lang: str, cfg: dict) -> dict:
    """保存済みの特徴から、🎧★と内訳を計算し直す(🎧の基準や重みを変えたとき)。測り直しではない。"""
    if not row.get("features"):
        return row
    feat = dict(row["features"])
    ear = scoring.ear_star(feat, lang, cfg)
    if ear is not None:
        feat["ear_parts"] = scoring.ear_parts(feat, lang, cfg)
    return {**row, "features": feat, "ear_star": ear}


def restar_ai(row: dict, cfg: dict) -> float | None:
    """保存済みの解析から、AI解析だけの点(total_star)を計算し直す。"""
    return scoring.total_star(row.get("calm_star"), row.get("ear_star"), row.get("interest_level"), cfg,
                              row.get("interest_score"))


def restar(row: dict, cfg: dict, store) -> tuple[float | None, str | None]:
    """保存済みの解析から、総合評点と final_reason を計算し直す(実測・みんなの評価が増えたとき、ルールを変えたとき)。"""
    _, final, reason = _stars(row.get("calm_star"), row.get("ear_star"), row.get("interest_level"),
                              row["episode_id"], cfg, store, row.get("interest_score"))
    return final, reason


def apply_judgement(j: dict, cfg: dict, store) -> dict:
    """セッションで判定した🌊🎯を、保存済みの解析に入れて★を計算し直す。

    j は config/rubric.md の出力形式(項目ごとの 0/1/2)に episode_id を足したもの。値の検証は llm.parse_judgement。
    """
    v = llm.parse_judgement(json.dumps(j, ensure_ascii=False), cfg)
    row = store.get("analysis", j["episode_id"])
    if row is None:
        raise KeyError(f"解析が見つかりません: {j['episode_id']}")
    total, final, final_reason = _stars(v["calm_star"], row.get("ear_star"), v["interest_level"], j["episode_id"],
                                        cfg, store, v["interest_score"])
    new = {**row, "calm_star": v["calm_star"], "interest_level": v["interest_level"],
           "interest_score": v["interest_score"],
           "total_star": total, "final_star": final, "final_reason": final_reason,
           "reasons": _reasons(row.get("reasons") or {}, v), **_new_outputs(v)}
    store.upsert("analysis", new)
    return new
