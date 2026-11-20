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


CALM_MINUTES = 20        # 1分ごとの起伏は、冒頭20分
PEAK_MIN = 1.0           # 山とみなす下限(1 = 少し)
PEAK_STRONG = 1.5        # これ以上の山は「多い」(level 2)、未満は「少し」(level 1)
MAX_PEAKS = 3
SUMMARY_MAX = 120


def calm_per_min(v) -> list[float] | None:
    """1分ごとの起伏の強さ(0〜2、小数1桁、最大20個)。形が違えば None(画面は図を出さない)。"""
    if not isinstance(v, list) or not v:
        return None
    out = []
    for x in v[:CALM_MINUTES]:
        if not isinstance(x, (int, float)) or isinstance(x, bool):
            return None
        out.append(round(min(2.0, max(0.0, float(x))), 1))
    return out


def calm_peaks(per_min: list[float], notes: list[dict]) -> list[dict]:
    """calm_per_min の山から、起伏の山(moments)を作る。[{min, note, level}](分の順、最大3件)。

    山 = PEAK_MIN 以上で、左より高く、右以上の分(平らな山は最初の分)。高い順に MAX_PEAKS 件。
    一言は、AIが書いた moments のうち、山の分に最も近いもの(前後1分まで)。一言のない山は出さない。
    """
    peaks = []
    for i, v in enumerate(per_min):
        left = per_min[i - 1] if i > 0 else -1.0
        right = per_min[i + 1] if i + 1 < len(per_min) else -1.0
        if v >= PEAK_MIN and v > left and v >= right:
            peaks.append((i, v))
    out, used = [], set()
    for i, v in sorted(peaks, key=lambda p: (-p[1], p[0])):
        cands = [(abs(int(n["min"]) - i), k) for k, n in enumerate(notes)
                 if k not in used and isinstance(n.get("min"), (int, float)) and abs(int(n["min"]) - i) <= 1
                 and str(n.get("note", "")).strip()]
        if not cands:
            continue
        _, k = min(cands)
        used.add(k)
        out.append({"min": i, "note": str(notes[k]["note"]).strip()[:20], "level": 2 if v >= PEAK_STRONG else 1})
        if len(out) == MAX_PEAKS:
            break
    return sorted(out, key=lambda m: m["min"])


def curve_consistent(per_min: list[float], calm_items: dict) -> bool:
    """1分ごとの起伏の線が、🌊 の4項目の点と食い違っていないか。

    - 4項目がすべて 0 なのに、線に「多い」(1.5 以上)がある → 食い違い
    - 1 以上を付けた項目があるのに、その分の前後1分(分が無ければ全体)で、線が 0.5 未満のまま → 食い違い
    """
    scored = [v for v in calm_items.values() if v["score"] > 0]
    if not scored:
        return max(per_min) < PEAK_STRONG
    for v in scored:
        m = v.get("min")
        window = per_min[max(0, m - 1): m + 2] if isinstance(m, int) and 0 <= m < len(per_min) else per_min
        if max(window) < 0.5:
            return False
    return True


def content_summary(v) -> str | None:
    """内容の要約(120字以内)。長すぎる・「！」を含むものは保存しない(画面は箱を出さない)。"""
    if not isinstance(v, str):
        return None
    t = " ".join(v.split())
    if not t or len(t) > SUMMARY_MAX or "！" in t or "!" in t:
        return None
    return t


CONTENT_START_MAX_SEC = 300   # 本編の開始は、冒頭5分まで(それより後なら、見つけられていないとみなす)
ANCHOR_MAX = 40


def content_start(v) -> dict | None:
    """本編が始まる位置: {"sec": 秒(0〜300), "anchor": 本編の最初の一言(40字以内)}。形が違えば None。

    sec = 0 は「冒頭から本編」(飛ばす所がない)。0 より大きいときは、anchor が必須(再生する音声は広告が差し替わって
    秒がずれるので、端末は anchor の一言で位置を合わせる)。anchor のない秒だけの値は、使えないので保存しない。
    """
    if not isinstance(v, dict):
        return None
    sec = v.get("sec")
    if not isinstance(sec, (int, float)) or isinstance(sec, bool) or not 0 <= sec <= CONTENT_START_MAX_SEC:
        return None
    anchor = " ".join(str(v.get("anchor") or "").split())[:ANCHOR_MAX]
    if sec > 0 and not anchor:
        return None
    return {"sec": int(round(sec)), "anchor": anchor or None}


def level_of(score: int) -> str:
    """引き込み力(1〜10)から3段階を決める。表示とユーザーの3択との比較用。"""
    return "low" if score <= 3 else "mid" if score <= 6 else "high"


def _default_cfg() -> dict:
    import yaml  # 遅延 import(cfg を渡されたときは、読まない)

    return yaml.safe_load((RUBRIC.parent / "scoring.yaml").read_text(encoding="utf-8"))


def parse_judgement(raw: str, cfg: dict | None = None) -> dict:
    """応答からJSONを取り出して検証する。不正なら ValueError。

    新形式: {"interest": {A..E: 0/1/2 または {"score", "min"}}, "calm": {A..D: 同}, "moments": [...], "reason": "..."}
      → 引き込み力 = 合計(0のとき1)、🌊★ = 5 − 合計×calm_slope(config/scoring.yaml)をコードで計算する(AIに★を直接付けさせない)。
    旧形式: {"calm_star", "interest_level", "reason"} も受ける。
    """
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise ValueError("JSON が見つかりません")
    d = json.loads(m.group(0))
    reason = str(d.get("reason", "")).strip()
    if "calm" in d and any(k in d for k in ("hook", "follow", "imagery")) and "interest" not in d:
        # 🎯を観察(分と引用つき)で出す形式。点(🎯★)は、保存済みの観察から、コードが計算する
        from . import observe
        ocfg = observe.load_config()
        cc = _items(d.get("calm"), CALM_ITEMS, "calm")
        from .scoring import calm_star as _calm_star
        calm = _calm_star(sum(v["score"] for v in cc.values()), cfg or _default_cfg())
        obs = observe.parse_interest(json.dumps(d, ensure_ascii=False), ocfg)
        per_min = calm_per_min(d.get("calm_per_min"))
        if per_min and not curve_consistent(per_min, cc):
            per_min = None
        notes = [x for x in (d.get("moments") or []) if isinstance(x, dict)]
        moments = calm_peaks(per_min, notes) if per_min else []
        return {"calm_star": calm, "interest_level": observe.interest_level(obs, ocfg), "interest_score": None, "reason": reason,
                "interest_obs": {k: obs[k] for k in ("hook", "follow", "imagery")},
                "items": {"interest": None, "calm": cc}, "moments": moments,
                "calm_per_min": per_min, "content_summary": content_summary(d.get("content_summary")),
                "content_start": content_start(d.get("content_start"))}
    if "interest" in d or "calm" in d:
        ii = _items(d.get("interest"), INTEREST_ITEMS, "interest")
        cc = _items(d.get("calm"), CALM_ITEMS, "calm")
        score = max(1, sum(v["score"] for v in ii.values()))
        from .scoring import calm_star as _calm_star

        calm = _calm_star(sum(v["score"] for v in cc.values()), cfg or _default_cfg())
        per_min = calm_per_min(d.get("calm_per_min"))
        if per_min and not curve_consistent(per_min, cc):
            per_min = None   # 4項目の点と食い違う線は保存しない(★は4項目から計算するので、線だけが別のことを言わないように)
        notes = [x for x in (d.get("moments") or []) if isinstance(x, dict)]
        if per_min:
            moments = calm_peaks(per_min, notes)
        else:  # 旧形式: 山の推移がなければ、AIが挙げた箇所をそのまま使う(強さは無し)
            moments = []
            for x in notes[:3]:
                if isinstance(x.get("min"), (int, float)) and str(x.get("note", "")).strip():
                    moments.append({"min": int(x["min"]), "note": str(x["note"]).strip()[:60]})
        return {"calm_star": calm, "interest_level": level_of(score), "interest_score": score, "reason": reason,
                "items": {"interest": ii, "calm": cc}, "moments": moments,
                "calm_per_min": per_min, "content_summary": content_summary(d.get("content_summary")),
                "content_start": content_start(d.get("content_start"))}
    calm = float(d["calm_star"])
    level = d["interest_level"]
    if not 1 <= calm <= 5 or level not in LEVELS:
        raise ValueError(f"範囲外の値: {d}")
    return {"calm_star": round(calm * 2) / 2, "interest_level": level, "interest_score": None, "reason": reason,
            "items": None, "moments": [], "calm_per_min": None, "content_summary": None, "content_start": None}


def judge(title: str, show_title: str, text: str, cfg: dict, client=None) -> dict:
    if client is None:
        import anthropic  # 遅延 import

        client = anthropic.Anthropic()
    msg = client.messages.create(
        model=cfg["llm"]["model"],
        max_tokens=cfg["llm"]["max_tokens"],
        messages=[{"role": "user", "content": build_prompt(title, show_title, text, cfg)}],
    )
    return parse_judgement("".join(b.text for b in msg.content if getattr(b, "type", "") == "text"), cfg)
