"""紹介サイト(静的HTML)を書き出す。掲載中の番組を、一覧と番組ごとのページで見せる。

データは公開キー(anon)で読める表と view だけを使う: show / episode / analysis / show_stats / show_sleep_points。
番組のページは、アプリの番組の詳細(ios/App/Screens/DetailView.swift・DetailCharts.swift)と同じ内容を出す。
文言と計算は ios/Sources/NeochiCore(Strings・Explain・DetailMath)に合わせる。変えるときは両方を直す。
言葉の決まりは docs/VOICE.md、用語は docs/SCORE.md。
"""
from __future__ import annotations

import json
import os
import re
import shutil
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime
from html import escape
from pathlib import Path
from statistics import mean

from . import strings
from .scoring import is_judged

ASSETS = Path(__file__).resolve().parent / "site_assets"

RANK_ORDER = {"ZZZ": 3, "ZZ": 2, "Z": 1}
# 格付けのひとこと(Strings.swift の rankMeaning と同じ)
RANK_MEANING = {"ZZZ": "眠りたい夜は、まずこの番組", "ZZ": "寝落ちのために選びたい番組", "Z": "寝落ちに向いた番組"}
# 格付けの線(config/z_rank.yaml と同じ値)
RANK_MIN = {"Z": 3.0, "ZZ": 3.6, "ZZZ": 4.2}

LEAD = "寝落ちに向いたポッドキャストを、評点と格付けで紹介しています。"
ENGLISH = "Neochi (n.) — Japanese for drifting off mid-episode. NeochiPickzz picks what to drift off to."
FOOT_NOTE = "評点は推定です。睡眠の良し悪しは評価していません。"
FOOT_RIGHTS = "番組名とカバー画像の権利は、各配信元にあります。音声は配信元で聴けます。"
EMPTY = "まだ掲載していません"
RANK_CRITERIA = ("寝落ち格付けは、番組の評点で決めます。"
                 + "、".join(f"{r} は{RANK_MIN[r]:.1f}以上" for r in ("Z", "ZZ", "ZZZ"))
                 + "です。基準に届かない番組は、掲載しません。評点は、AI解析を土台に、ウォッチの実測とみんなの評価が集まるほど、それらを足したものです。")

INTEREST_LABELS = {"A": "未解決の問い", "B": "驚き・新しい情報", "C": "笑い", "D": "追い続ける必要", "E": "聴き手への働きかけ"}
CALM_LABELS = {"A": "感情の強さ", "B": "対立・緊張", "C": "頭の負荷", "D": "急な転換"}
INTEREST_WORD = {"low": "静かめ", "mid": "程よい", "high": "強め"}
SLEEP_ZONE_NOTE = "再生を始めてから、30分未満で眠れた記録は、寝落ちしたとみなします。"


# ---------- データ ----------

def fetch_public(url: str, key: str) -> dict:
    """公開キーで、サイトに出す表を読む。view がまだ無い環境では、その表を空にする。"""
    base = url.rstrip("/") + "/rest/v1/"

    def get(path: str, select: str, extra: dict | None = None, optional: bool = False) -> list[dict]:
        q = {"select": select, **(extra or {})}
        req = urllib.request.Request(base + path + "?" + urllib.parse.urlencode(q),
                                     headers={"apikey": key, "Authorization": f"Bearer {key}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError:
            if optional:
                return []
            raise

    return {
        "show": get("show", "id,title,publisher,genre,lang,show_star,z_rank,listing_status,artwork_url,link_url,apple_url"),
        "episode": get("episode", "id,show_id,title,duration_sec,published_at,link_url", {"order": "published_at.desc"}),
        "analysis": get("analysis", "episode_id,calm_star,ear_star,final_star,interest_level,interest_score,input_depth,"
                                    "reasons,features,calm_per_min,content_summary"),
        "show_stats": get("show_stats", "*", optional=True),
        "show_sleep_points": get("show_sleep_points", "show_id,night,latency_min", {"order": "night.asc"}, optional=True),
    }


def load_json_store(path: str | Path) -> dict:
    """data/store.json(Supabase 未設定時の保存先)から読む。"""
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    return {t: list(v.values()) if isinstance(v, dict) else v for t, v in raw.items()}


def build_model(data: dict, cfg: dict) -> list[dict]:
    """掲載中で格付けがあり、判定済みの回がある番組だけを、評点の高い順に返す(docs/SCORE.md §1)。"""
    eps_by_show: dict[str, list[dict]] = {}
    for e in data.get("episode", []):
        eps_by_show.setdefault(e["show_id"], []).append(e)
    an = {a["episode_id"]: a for a in data.get("analysis", [])}
    stats = {s["show_id"]: s for s in data.get("show_stats", [])}
    points: dict[str, list[dict]] = {}
    for p in sorted(data.get("show_sleep_points", []), key=lambda p: p["night"]):
        points.setdefault(p["show_id"], []).append(p)

    shows = []
    for s in data.get("show", []):
        if s.get("listing_status") != "listed" or s.get("z_rank") not in RANK_ORDER or s.get("show_star") is None:
            continue
        eps = sorted(eps_by_show.get(s["id"], []), key=lambda e: e.get("published_at") or "", reverse=True)
        analyzed = [(e, an[e["id"]]) for e in eps if e["id"] in an]
        scored = [(e, a) for e, a in analyzed if a.get("final_star") is not None and is_judged(a)]
        if not any(is_judged(a) for _, a in analyzed):
            # 判定済みの回がない番組は掲載しない。DB の格付けが古いままでも、サイトには出さない。
            continue
        shows.append({**s, "show_star": float(s["show_star"]), "episodes": eps, "analyzed": analyzed,
                      "scored": scored, "stats": stats.get(s["id"]), "points": points.get(s["id"], [])})
    shows.sort(key=lambda s: (-s["show_star"], -RANK_ORDER[s["z_rank"]], s["title"]))
    return shows


# ---------- 計算(NeochiCore の Explain・DetailMath と同じ) ----------

def episode_number(title: str) -> int | None:
    pats = [r"第\s*(\d{1,5})\s*[回話]", r"#\s*(\d{1,5})", r"(\d{1,5})\s*[回話]",
            r"(?i)\bep(?:isode)?\.?\s*(\d{1,5})", r"^\s*(\d{1,5})[\.\s:：]"]
    for p in pats:
        m = re.search(p, title or "")
        if m:
            return int(m.group(1))
    return None


def delta(values: list[float]) -> float | None:
    """直近4件の平均 − その前の4件の平均。values は古い順。8件未満なら None。"""
    if len(values) < 8:
        return None
    return mean(values[-4:]) - mean(values[-8:-4])


def _unit(v: float, best: float, worst: float) -> float:
    return 1.0 if best == worst else max(0.0, min(1.0, (v - worst) / (best - worst)))


def _pick(u: float, good: str, mid: str, bad: str) -> str:
    return good if u >= 0.7 else mid if u >= 0.3 else bad


def ear_criteria(cfg: dict, lang: str = "ja") -> dict:
    e = cfg["ear"]
    r = e["rate"].get(lang) or e["rate"]["ja"]
    return {"rate_best": r["best_max"], "rate_worst": r["worst"], "cv_best": e["rate_cv"]["best"], "cv_worst": e["rate_cv"]["worst"],
            "vol_best": e["volume_std_db"]["best"], "vol_worst": e["volume_std_db"]["worst"],
            "sud_best": e["sudden_per_10min"]["best"], "sud_worst": e["sudden_per_10min"]["worst"]}


def ear_parts(f: dict, c: dict) -> list[dict]:
    """耳のゆるさの4項目。何を測って、どうだったか、基準はどこか。"""
    p = f.get("ear_parts") or {}
    out = []
    if f.get("speech_rate") is not None:
        r = f["speech_rate"]
        u = 1.0 if r <= c["rate_best"] else _unit(r, c["rate_best"], c["rate_worst"])
        out.append({"title": "話す速さ", "star": p.get("rate"), "short": f"{round(r)}字/分", "fill": u,
                    "verdict": _pick(u, "寝落ちに向く速さです", "やや速めです", "かなり速いです"),
                    "criterion": f"{c['rate_best']}字/分までは満点、{c['rate_worst']}字で最低"})
    if f.get("speech_rate_cv") is not None:
        cv = f["speech_rate_cv"]
        u = _unit(cv, c["cv_best"], c["cv_worst"])
        out.append({"title": "速さのばらつき", "star": p.get("rate_cv"), "short": f"{round(cv * 100)}%", "fill": u,
                    "verdict": _pick(u, "速さがほぼ一定です", "速さが、ところどころ変わります", "速さが大きく揺れます"),
                    "criterion": f"揺れが{round(c['cv_best'] * 100)}%以下なら満点、{round(c['cv_worst'] * 100)}%で最低"})
    if f.get("volume_std_db") is not None:
        d = f["volume_std_db"]
        u = _unit(d, c["vol_best"], c["vol_worst"])
        out.append({"title": "音量の変化", "star": p.get("volume"), "short": f"{d:.1f}dB", "fill": u,
                    "verdict": _pick(u, "音量が安定しています", "音量に、ところどころ大小があります", "音量が大きく上下します"),
                    "criterion": f"{c['vol_best']}dB以下なら満点、{c['vol_worst']}dBで最低"})
    if f.get("sudden_per_10min") is not None:
        s = f["sudden_per_10min"]
        u = _unit(s, c["sud_best"], c["sud_worst"])
        out.append({"title": "突発音", "star": p.get("sudden"), "short": f"{s:.1f}回/10分", "fill": u,
                    "verdict": _pick(u, "急に大きな音は、ほとんどありません", "急な音が、ときどきあります", "急な音が多めです"),
                    "criterion": f"0回なら満点、{c['sud_worst']}回で最低(屋外の音や、音の演出が多い回は、多めに数えます)"})
    return out


def items(d: dict | None) -> list[dict]:
    return [{"key": k, "score": int(v.get("score") or 0), "min": v.get("min")} for k, v in sorted((d or {}).items())]


def calm_verdict(its: list[dict]) -> str:
    s = sum(i["score"] for i in its)
    return "気持ちや頭を昂らせる要素は、見当たりませんでした" if s == 0 else f"昂らせる要素が合計{s}点ありました(0点に近いほど、穏やかです)"


def calm_curve_verdict(moments: list[dict], minutes: int) -> str:
    strong = sum(1 for m in moments if m.get("level") == 2)
    if not moments:
        return f"冒頭{minutes}分に、昂らせる山はありません。"
    if strong == 0:
        return f"冒頭{minutes}分に、小さな山が{len(moments)}つだけです。"
    return f"冒頭{minutes}分に山が{len(moments)}つ、うち{strong}つは強めです。"


def moment_strength(m: dict) -> str:
    return {1: "少し", 2: "多い"}.get(m.get("level"), "")


def level_word(score: int) -> str:
    return {0: "なし", 1: "少し"}.get(score, "多い")


# ---------- 表示の部品 ----------

def breakdown(stats: dict | None) -> str:
    """評点の内訳。あるものだけ並べる(Strings.swift の ratingBreakdown と同じ)。"""
    n = int((stats or {}).get("n") or 0)
    if n >= 3:
        return f"AI解析・寝落ちまで 平均{stats['avg_min']}分(ウォッチの実測 {n}件)"
    return "AI解析"


def fmt_md(iso: str | None) -> str:
    if not iso:
        return ""
    try:
        d = datetime.fromisoformat(iso.replace("Z", "+00:00")) if "T" in iso else datetime.combine(date.fromisoformat(iso), datetime.min.time())
    except ValueError:
        return ""
    return f"{d.month}/{d.day}"


def n1(v: float | None) -> str:
    return "―" if v is None else f"{float(v):.1f}"


def mark_svg(cls: str = "mark") -> str:
    """ロゴの記号 N。3本の線の濃さは design/tokens.json の opacity-logo-1〜3(アプリアイコンと同じ形)。"""
    return (f'<svg class="{cls}" viewBox="300 270 425 485" aria-hidden="true" fill="none" stroke="currentColor" '
            'stroke-width="71" stroke-linecap="round">'
            '<path d="M689.5 305.5V719" opacity=".28"/><path d="M335.5 305.5L689.5 719" opacity=".6"/>'
            '<path d="M335.5 305.5V719"/></svg>')


def wordmark(root: str) -> str:
    return (f'<a class="logo" href="{root}" aria-label="NeochiPickzz トップ">{mark_svg("logo-n")}'
            '<span aria-hidden="true">eochiPick<span class="z1">z</span><span class="z2">z</span></span></a>')


def badge(rank: str, small: bool = False) -> str:
    return f'<span class="badge badge-{rank.lower()}{" badge-s" if small else ""}" aria-label="寝落ち格付け {rank}">{rank}</span>'


def star(v: float | None, cls: str = "star") -> str:
    return f'<span class="{cls}" aria-label="評点 {n1(v)}"><span class="star-glyph">★</span>{n1(v)}</span>'


def artwork(url: str | None, cls: str) -> str:
    if not url:
        return f'<span class="art {cls} art-empty" aria-hidden="true">{mark_svg()}</span>'
    return f'<img class="art {cls}" src="{escape(url)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer">'


ARROW = {"up": '<path d="M3 9L9 3M4 3h5v5"/>', "down": '<path d="M3 3l6 6M9 4v5H4"/>', "flat": '<path d="M2.5 4.5h7M2.5 7.5h7"/>'}


def delta_pill(d: float, higher_is_better: bool, fmt, caption: str) -> str:
    text = fmt(abs(d))
    flat = text == fmt(0)
    tone = "flat" if flat or d == 0 else ("pos" if (d > 0) == higher_is_better else "neg")
    arrow = "flat" if flat else "up" if d > 0 else "down"
    return (f'<span class="pill pill-{tone}"><svg viewBox="0 0 12 12" aria-hidden="true">{ARROW[arrow]}</svg>'
            f'<b>{text}</b><span>{caption}</span></span>')


def page(*, title: str, desc: str, root: str, body: str, canonical: str = "", og_image: str = "",
         og_type: str = "website", large_card: bool = False) -> str:
    meta = [
        f'<meta name="description" content="{escape(desc)}">',
        f'<meta property="og:title" content="{escape(title)}">',
        f'<meta property="og:description" content="{escape(desc)}">',
        f'<meta property="og:type" content="{og_type}">',
        '<meta property="og:site_name" content="NeochiPickzz">',
        '<meta property="og:locale" content="ja_JP">',
        f'<meta name="twitter:card" content="{"summary_large_image" if large_card else "summary"}">',
    ]
    if canonical:
        meta += [f'<link rel="canonical" href="{escape(canonical)}">', f'<meta property="og:url" content="{escape(canonical)}">']
    if og_image:
        meta.append(f'<meta property="og:image" content="{escape(og_image)}">')
    return f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)}</title>
{chr(10).join(meta)}
<meta name="theme-color" content="#171C33">
<link rel="icon" href="{root}favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="{root}apple-touch-icon.png">
<link rel="stylesheet" href="{root}style.css">
</head>
<body>
<header class="top"><div class="wrap">{wordmark(root)}<nav><a href="{root}about/">解析について</a></nav></div></header>
<main class="wrap">
{body}
</main>
<footer class="foot"><div class="wrap">
{wordmark(root)}
<p>{FOOT_NOTE}</p>
<p>{FOOT_RIGHTS}</p>
</div></footer>
</body>
</html>
"""


# ---------- 一覧 ----------

def index_html(shows: list[dict]) -> str:
    counts: dict[str, int] = {}
    for s in shows:
        if s.get("genre"):
            counts[s["genre"]] = counts.get(s["genre"], 0) + 1
    genres = sorted(counts, key=lambda g: -counts[g])
    rows = []
    for s in shows:
        search = f"{s['title']} {s.get('publisher') or ''} {s.get('genre') or ''}".lower()
        sub = escape(s.get("genre") or "") + (" · " + escape(s["publisher"]) if s.get("publisher") else "")
        rows.append(f"""<li class="row" data-rank="{s['z_rank']}" data-genre="{escape(s.get('genre') or '')}" data-q="{escape(search)}">
<a href="shows/{s['id']}/">
<span class="art-wrap">{artwork(s.get('artwork_url'), 'art-s')}{badge(s['z_rank'], small=True)}</span>
<span class="row-text"><span class="row-title">{escape(s['title'])}</span><span class="row-sub">{sub}</span></span>
{star(s['show_star'])}
</a></li>""")
    chips = "".join(f'<button type="button" class="chip" data-genre="{escape(g)}" aria-pressed="false">{escape(g)}</button>' for g in genres)
    ranks = "".join(f'<button type="button" class="chip" data-rank="{r}" aria-pressed="false">{r}</button>' for r in ("ZZZ", "ZZ", "Z"))
    return f"""<section class="hero">
{mark_svg("hero-mark")}
<h1>{strings.TAGLINE}</h1>
<p class="lead">{LEAD}</p>
<p class="count">掲載 <b>{len(shows)}</b>番組</p>
</section>
<section class="filters" aria-label="絞り込み">
<input id="q" type="search" placeholder="番組名・配信者で探す" aria-label="番組名・配信者で探す" autocomplete="off">
<div class="chips" role="group" aria-label="寝落ち格付け">{ranks}</div>
<div class="chips" role="group" aria-label="ジャンル">{chips}</div>
</section>
<ul class="list" id="list">
{chr(10).join(rows)}
</ul>
<p class="empty" id="empty" hidden>{EMPTY}</p>
<script>{FILTER_JS}</script>"""


# ---------- 番組の詳細(アプリの DetailView と同じ並び) ----------

# 図は横を % で置く(幅が変わっても、文字と点の大きさは変わらない)。線と面は内側の svg に、横 0〜20 分の座標で描き、縦横比を固定しない。
PL, PR = 11.0, 98.0   # 図の左端・右端(%)。左は縦軸の目盛りの場所


def _px(m: float, lo: float = 0, hi: float = 20, pl: float = PL, pr: float = PR) -> str:
    return f"{pl + (pr - pl) * (min(max(m, lo), hi) - lo) / (hi - lo):.2f}%"


def _plot(inner: str, top: float, height: float, x_hi: float = 20) -> str:
    return (f'<svg x="{PL}%" y="{top}" width="{PR - PL}%" height="{height}" viewBox="0 0 {x_hi} {height}" '
            f'preserveAspectRatio="none" overflow="visible">{inner}</svg>')


def calm_chart(values: list[float], moments: list[dict]) -> str:
    """1分ごとの起伏の線と山の点。山の点を押すと、上の行にその山の内容が出る。"""
    H, T, B = 132, 8, 20
    ph = H - T - B
    yl = lambda v: ph * (1 - v / 2)        # 内側の座標
    y = lambda v: T + yl(v)                # 外側の座標
    line = " ".join(f"{i},{yl(v):.1f}" for i, v in enumerate(values))
    area = f"0,{yl(0):.1f} {line} {len(values) - 1},{yl(0):.1f}"
    grid = "".join(f'<line class="grid" x1="{PL}%" x2="{PR}%" y1="{y(v):.1f}" y2="{y(v):.1f}"/>'
                   f'<text class="ax" x="{PL - 1.5}%" y="{y(v) + 3:.1f}" text-anchor="end">{w}</text>'
                   for v, w in ((0, "なし"), (1, "少し"), (2, "多い")))
    xt = "".join(f'<text class="ax num" x="{_px(m)}" y="{H - 4}" text-anchor="middle">{m}</text>' for m in (0, 5, 10, 15, 20))
    plot = _plot(f'<polygon class="area" points="{area}"/><polyline class="line" vector-effect="non-scaling-stroke" points="{line}"/>', T, ph)
    dots = []
    for i, m in enumerate(moments):
        v = values[m["min"]] if 0 <= m["min"] < len(values) else 0
        label = escape(f"{m['min']}分の山。{m['note']}" + (f"、{moment_strength(m)}" if moment_strength(m) else ""))
        dots.append(f'<g class="peak{" on" if i == 0 else ""}" tabindex="0" role="button" aria-label="{label}" '
                    f'data-min="{m["min"]}" data-note="{escape(m["note"])}" data-level="{moment_strength(m)}">'
                    f'<circle class="hit" cx="{_px(m["min"])}" cy="{y(v):.1f}" r="14"/>'
                    f'<circle class="dot" cx="{_px(m["min"])}" cy="{y(v):.1f}" r="5"/></g>')
    first = moments[0] if moments else None
    pick = (f'<p class="moment-pick" aria-live="polite"><b>{first["min"]}分</b> {escape(first["note"])} '
            f'<span>{moment_strength(first)}</span></p>') if first else ""
    return (f'<div class="calm-chart">{pick}<svg height="{H}" role="img" aria-label="起伏の強さ(1分ごと、AIの推定)">'
            f'{grid}{plot}{xt}{"".join(dots)}</svg></div>')


def ear_charts(f: dict, c: dict) -> str:
    tl = f.get("timeline") or {}
    rate = [(i, v) for i, v in enumerate(tl.get("rate_per_min") or []) if v is not None and i <= 20]
    vol = [(i, v) for i, v in enumerate(tl.get("volume_db") or []) if v is not None and i <= 20]
    sudden = [s / 60 for s in (tl.get("sudden_at_sec") or []) if s / 60 <= 20][:60]
    if not rate and not vol:
        return ""
    H, T = 104, 16

    def chart(pts, lo, hi, band, yticks, title, unit, extra=None, axis=True):
        B = 18 if axis else 6
        ph = H - T - B
        yl = lambda v: ph * (1 - (v - lo) / (hi - lo))
        y = lambda v: T + yl(v)
        line = " ".join(f"{i},{yl(v):.1f}" for i, v in pts)
        inner = (f'<rect class="band" x="0" width="20" y="{yl(band[1]):.1f}" height="{yl(band[0]) - yl(band[1]):.1f}"/>'
                 f'<polyline class="line" vector-effect="non-scaling-stroke" points="{line}"/>')
        xt = "".join(f'<line class="grid" x1="{_px(m)}" x2="{_px(m)}" y1="{T}" y2="{H - B}"/>' for m in (0, 5, 10, 15, 20))
        if axis:
            xt += "".join(f'<text class="ax num" x="{_px(m)}" y="{H - 4}" text-anchor="middle">{m}</text>' for m in (0, 5, 10, 15, 20))
        yt = "".join(f'<text class="ax num" x="{PL - 1.5}%" y="{y(v) + 3:.1f}" text-anchor="end">{t}</text>' for v, t in yticks)
        return (f'<div class="ear-chart"><p class="chart-label"><span>{title}</span><span>{unit}</span></p>'
                f'<svg height="{H}" role="img" aria-label="{title}">{xt}{_plot(inner, T, ph)}{yt}{extra(y) if extra else ""}</svg></div>')

    out = []
    if rate:
        top = max(c["rate_worst"], max(v for _, v in rate) + 40)
        mx = max(rate, key=lambda p: p[1])
        marked = {rate[0][0], mx[0], rate[-1][0]}

        def marks(y):
            return "".join(f'<circle class="pt" cx="{_px(i)}" cy="{y(v):.1f}" r="3"/>'
                           f'<text class="val num" x="{_px(i)}" y="{y(v) - 6:.1f}" text-anchor="middle">{round(v)}</text>'
                           for i, v in rate if i in marked)
        out.append(chart(rate, 0, top, (0, c["rate_best"]), [(c["rate_best"], c["rate_best"])], "話す速さ", "字/分", marks, axis=not vol))
    if vol:
        band = c["vol_best"]
        span = max(band * 2, max(abs(v) for _, v in vol) + 2)

        def ticks(y):
            return "".join(f'<line class="tick" x1="{_px(m)}" x2="{_px(m)}" y1="{y(-span):.1f}" y2="{y(-span + span * 0.3):.1f}"/>'
                           for m in sudden)
        out.append(chart(vol, -span, span, (-band, band), [(-band, f"-{band}"), (0, "0"), (band, f"+{band}")],
                         "音量", "中央値との差 dB", ticks))
    legend = ('<p class="legend"><span><i class="lg-band"></i>寝落ちに向く範囲</span>'
              + ('<span><i class="lg-tick"></i>突発音</span>' if vol else "") + '<span class="grow">横軸は分</span></p>')
    return "".join(out) + legend


def item_rows(its: list[dict], labels: dict) -> str:
    rows = []
    for it in its:
        mins = f'<span class="cap">{it["min"]}分ごろ</span>' if it["min"] is not None and it["score"] > 0 else ""
        dots = "".join(f'<i class="{"on" if i < it["score"] else ""}"></i>' for i in range(2))
        rows.append(f'<li><span>{labels.get(it["key"], it["key"])}</span>{mins}'
                    f'<span class="lv{" on" if it["score"] > 0 else ""}">{level_word(it["score"])}</span><span class="dots">{dots}</span></li>')
    return f'<ul class="items">{"".join(rows)}</ul>'


def part_rows(parts: list[dict]) -> str:
    return '<ul class="parts">' + "".join(
        f'<li aria-label="{p["title"]}。{p["short"]}。{p["verdict"]}。評点 {n1(p["star"])}"><span>{p["title"]}</span>'
        f'<span class="num">{p["short"]}</span><span class="gauge"><span style="width:{max(4, p["fill"] * 100):.0f}%"></span></span>'
        f'<span class="num fac">{n1(p["star"])}</span></li>' for p in parts) + "</ul>"


def interest_scale(total: int) -> str:
    cells = "".join(f'<span class="{"zone " if 4 <= i <= 6 else ""}{"on" if i == total else ""}"><i></i><b>{i}</b></span>'
                    for i in range(1, 11))
    return f'<div class="scale" role="img" aria-label="引き込み力 {total}、10段階。4〜6が寝落ち向き">{cells}</div><p class="cap">4〜6が寝落ち向き</p>'


def axis_row(title: str, value_html: str, body: str, open_: bool = False) -> str:
    return (f'<details class="axis"{" open" if open_ else ""}><summary><span>{title}</span><span class="axis-v">{value_html}</span>'
            f'<svg class="chev" viewBox="0 0 12 12" aria-hidden="true"><path d="M4 2l4 4-4 4"/></svg></summary>'
            f'<div class="axis-body">{body}</div></details>')


def evidence(e: dict, a: dict, cfg: dict, lang: str) -> str:
    f = a.get("features") or {}
    r = a.get("reasons") or {}
    its = r.get("items") or {}
    calm_items, int_items = items(its.get("calm")), items(its.get("interest"))
    moments = r.get("moments") or []
    rows = []
    # 起伏の少なさ: 判定の一行 → 1分ごとの起伏の線 → 4項目 → 計算式の注記
    if a.get("calm_star") is not None:
        per = [float(v) for v in (a.get("calm_per_min") or [])]
        body = ""
        if per:
            body += f'<p>{calm_curve_verdict(moments, len(per))}</p><p class="cap">起伏の強さ(1分ごと、AIの推定)</p>'
            body += calm_chart(per, [m for m in moments if m["min"] < len(per)])
        elif calm_items:
            body += f"<p>{calm_verdict(calm_items)}</p>"
        if calm_items:
            body += item_rows(calm_items, CALM_LABELS) + '<p class="cap">項目は 0〜2 点。合計が小さいほど、★が多くなります(5 − 合計×0.5)</p>'
        if not per and moments:
            body += '<ul class="moments">' + "".join(f'<li><b class="num fac">{m["min"]}分</b> {escape(m["note"])}</li>' for m in moments) + "</ul>"
        rows.append(axis_row("起伏の少なさ", star(a["calm_star"], "star"), body, open_=True))
    else:
        rows.append(f'<div class="axis pending"><span>起伏の少なさ</span><span class="cap">判定待ち</span></div>')
    # 耳のゆるさ: 話す速さと音量の図 → 4項目
    if a.get("ear_star") is not None:
        c = ear_criteria(cfg, lang)
        rows.append(axis_row("耳のゆるさ", star(a["ear_star"], "star"), ear_charts(f, c) + part_rows(ear_parts(f, c))))
    # 程よい興味: 内容の要約 → 5項目 → 10段の目盛り
    lv = a.get("interest_level")
    if lv:
        total = a.get("interest_score") or max(1, sum(i["score"] for i in int_items))
        body = ""
        if a.get("content_summary"):
            body += f'<div class="summary"><p class="cap">この回の内容(AIの要約)</p><p>{escape(a["content_summary"])}</p></div>'
        if int_items:
            body += item_rows(int_items, INTEREST_LABELS)
        body += interest_scale(int(total))
        rows.append(axis_row("程よい興味", f'<span class="fac">{INTEREST_WORD.get(lv, lv)}</span>', body))
    else:
        rows.append(f'<div class="axis pending"><span>程よい興味</span><span class="cap">判定待ち</span></div>')
    n = episode_number(e.get("title") or "")
    head = f"{n}回の解析" if n else "最新の回の解析"
    return (f'<section class="sec"><div class="sec-head"><h2>観点ごとの根拠</h2><span class="cap">{head}</span></div>'
            f'<div class="axes-card">{"".join(rows)}</div></section>')


def sleep_axis(points: list[dict]) -> str:
    """寝落ちの実績: 0〜60分の軸に記録を点で置く。30分未満は塗り、30分以上は線だけ。点に日付と分数。"""
    x = lambda m: _px(m, 0, 60, 2, 98)
    mins = [p["latency_min"] for p in points]
    zones = ('<rect class="zone-fell" x="2%" y="18" width="48%" height="40"/>'
             '<rect class="zone-rest" x="50%" y="18" width="48%" height="40"/>'
             '<text class="ax fell" x="26%" y="86" text-anchor="middle">寝落ちした</text>'
             '<text class="ax" x="74%" y="86" text-anchor="middle">30分以上</text>'
             '<line class="grid" x1="2%" x2="98%" y1="58" y2="58"/>')
    ticks = "".join(f'<text class="ax num" x="{x(t)}" y="70" text-anchor="middle">{t}</text>' for t in (0, 15, 30, 45, 60))
    dots = "".join(f'<circle class="{"sd fill" if p["latency_min"] < 30 else "sd"}" cx="{x(p["latency_min"])}" cy="38" r="5">'
                   f'<title>{fmt_md(p["night"])}  {p["latency_min"]}分</title></circle>' for p in points)
    ext = "".join(f'<text class="val num" x="{x(m)}" y="13" text-anchor="middle">{m}</text>' for m in sorted({min(mins), max(mins)})) if len(mins) >= 2 else ""
    return f'<svg class="sleep-axis" height="92" role="img" aria-label="寝落ちの実績 {len(points)}件">{zones}{ticks}{dots}{ext}</svg>'


def record(s: dict) -> str:
    pts, st = s["points"], s["stats"]
    mins = [p["latency_min"] for p in pts]
    avg = round(mean(mins)) if mins else (st or {}).get("avg_min")
    if avg is None:
        return ""   # データがない間は、欄ごと出さない
    head = '<div class="sec-head"><h2>寝落ちの実績</h2><span class="cap">再生を始めてから眠るまで(ウォッチの実測)</span></div>'
    d = delta([float(m) for m in mins])
    pill = delta_pill(d, False, lambda v: f"{round(v)}分", "前の4件") if d is not None else ""
    body = (f'<div class="row-between"><span><span class="cap">平均</span> <b class="num big res">{avg}</b>'
            f'<span class="res">分</span></span>{pill}</div>')
    if mins:
        body += (sleep_axis(pts) + f'<p class="legend"><span><i class="lg-fill"></i>30分未満 {sum(m < 30 for m in mins)}件</span>'
                 f'<span><i class="lg-ring"></i>30分以上 {sum(m >= 30 for m in mins)}件</span></p><p class="cap">{SLEEP_ZONE_NOTE}</p>')
    elif st:
        body += (f'<p>最短 {st["min_min"]}分、最長 {st["max_min"]}分。{st["n"]}件のうち {st["under30"]}件が、'
                 "30分より前に寝落ちしました。</p>")
    return f'<section class="sec">{head}<div class="card">{body}</div></section>'


def recent(s: dict) -> str:
    """最近の回の評点。判定済みの回を直近8回まで(古い順)。それより新しい未判定の回は「解析中」として2回まで。"""
    scored = s["scored"]
    if len(scored) < 2:
        return ""
    newest = scored[0][0]
    idx = next(i for i, e in enumerate(s["episodes"]) if e["id"] == newest["id"])
    an = {e["id"]: a for e, a in s["analyzed"]}
    pending = [e for e in s["episodes"][:idx] if not (e["id"] in an and is_judged(an[e["id"]]))][:2]

    def label(e):
        n = episode_number(e.get("title") or "")
        return f"{n}回" if n else fmt_md(e.get("published_at"))
    cols = [(label(e), None, False, e) for e in pending] + [(label(e), float(a["final_star"]), e["id"] == newest["id"], e) for e, a in scored[:8]]
    cols.reverse()
    vals = [v for _, v, _, _ in cols if v is not None]
    avg = mean(vals)
    d = delta(vals)
    pill = delta_pill(d, True, lambda v: f"{v:.1f}", "前の4回") if d is not None else ""
    bars = []
    for lab, v, latest, e in cols:
        t = escape(e.get("title") or "")
        if v is None:
            bars.append(f'<div class="bar" title="{t}"><span class="cap">解析中</span><i class="pend"></i><span class="num cap">{lab}</span></div>')
        else:
            bars.append(f'<div class="bar{" latest" if latest else ""}" title="{t}"><span class="num v">{v:.1f}</span>'
                        f'<i style="height:{v / 5 * 88:.0f}px"></i><span class="num cap">{lab}</span></div>')
    return (f'<section class="sec"><div class="sec-head"><h2>最近の回</h2><span class="cap">回ごとの評点</span></div>'
            f'<div class="card"><div class="row-between"><span><b class="num big fac">{avg:.1f}</b> <span class="cap">{len(vals)}回の平均</span></span>{pill}</div>'
            f'<div class="bars" style="--avg:{avg / 5 * 88:.0f}px">{"".join(bars)}</div></div></section>')


def about_block(a: dict | None, cfg: dict, lang: str) -> str:
    if a is None:
        return '<p class="cap">この番組の解析は、まだありません。</p>'
    depth = {"audio": "音響の分析だけで判定しています。", "transcript": "冒頭を文字起こしして判定しています。"}.get(
        a.get("input_depth"), "番組の説明文だけで判定しています。")
    probe = {"speech_rate": 0, "speech_rate_cv": 0, "volume_std_db": 0, "sudden_per_10min": 0}
    crit = "<br>".join(f'{p["title"]}: {p["criterion"]}' for p in ear_parts(probe, ear_criteria(cfg, lang)))
    return (f'<details class="about"><summary>解析について</summary><div class="cap">'
            f"<p>耳のゆるさの基準(★5が満点、★1が最低)<br>{crit}</p>"
            "<p>音量の推移と突発音は、冒頭30分を測っています。話す速さと、起伏・興味の判定は、冒頭を文字起こしして行っています。"
            f"30分以降を聴くのは寝つけなかったときだけなので、内容の評価は冒頭20分までにしています。{depth}</p>"
            f"<p>{RANK_CRITERIA}</p></div></details>")


def show_html(s: dict, base_url: str, cfg: dict) -> str:
    lang = s.get("lang") or "ja"
    latest = s["analyzed"][0] if s["analyzed"] else None
    st = s["stats"]
    sub = escape(s["episodes"][0].get("title") or "") if s["episodes"] else ""
    avg = (st or {}).get("avg_min") if (st or {}).get("n") else None
    duo = (f'<section class="duo"><div><p class="cap">評点</p>{star(s["show_star"], "star big")}</div><span class="vr"></span>'
           f'<div><p class="cap">寝落ちまで(ウォッチの実測の平均)</p>'
           + (f'<p><b class="num big res">{avg}</b><span class="res">分</span></p>' if avg is not None else '<p class="num big muted">―</p>')
           + f'</div></section><p class="cap">{breakdown(st)}</p>')
    links = []
    if s.get("apple_url"):
        links.append(f'<a class="btn" href="{escape(s["apple_url"])}" rel="noopener" target="_blank">Apple Podcasts で聴く</a>')
    if s.get("link_url"):
        links.append(f'<a class="btn{" btn-ghost" if links else ""}" href="{escape(s["link_url"])}" rel="noopener" target="_blank">配信元で聴く</a>')
    url = f"{base_url}shows/{s['id']}/" if base_url else ""
    share_text = f"{s['title']}。評点 ★ {s['show_star']:.1f}、寝落ち格付け {s['z_rank']}。"
    x_url = "https://x.com/intent/post?" + urllib.parse.urlencode({"text": share_text, **({"url": url} if url else {})})
    parts = [f"""<p class="back"><a href="../../">一覧へ</a></p>
<section class="detail-head">
{artwork(s.get('artwork_url'), 'art-l')}
<div class="detail-title">
<p class="rank-line">{badge(s['z_rank'])}<span class="cap">{RANK_MEANING[s['z_rank']]}</span></p>
<h1>{escape(s['title'])}</h1>
<p class="cap one-line">{sub}</p>
</div>
</section>
{duo}
<section class="actions">{''.join(links)}
<a class="btn btn-ghost" href="{escape(x_url)}" rel="noopener" target="_blank">X で共有</a>
<button type="button" class="btn btn-ghost" id="copy" data-url="{escape(url)}">リンクをコピー</button>
<span class="cap" id="copied" hidden>コピーしました</span>
</section>"""]
    if latest:
        e, a = latest
        line = (a.get("reasons") or {}).get("llm")
        if line:
            parts.append(f'<section class="sec"><div class="card"><h2>AI解析</h2><p>{escape(line)}</p></div></section>')
        if any(a.get(k) is not None for k in ("calm_star", "ear_star", "interest_level")):
            parts.append(evidence(e, a, cfg, lang))
    parts.append(record(s))
    parts.append(recent(s))
    parts.append(about_block(latest[1] if latest else None, cfg, lang))
    parts.append(f"<script>{DETAIL_JS}</script>")
    return "\n".join(p for p in parts if p)


def about_html() -> str:
    return f"""<section class="prose">
{mark_svg("hero-mark")}
<h1>解析について</h1>
<p class="en">{ENGLISH}</p>
<h2>評点</h2>
<p>番組が寝落ちに向いた作りかを、1.0〜5.0の★で表します。3つの観点を合わせた点です。</p>
<dl>
<dt>{strings.LABEL_INTEREST}</dt><dd>少し気になるが、追わなくても困らないくらいが、いちばん高くなります。冒頭を文字起こしして判定しています。</dd>
<dt>{strings.LABEL_CALM}</dt><dd>盛り上がり、驚き、対立、急な話題の転換が少ないほど、高くなります。</dd>
<dt>{strings.LABEL_EAR}</dt><dd>話す速さ、速さのばらつき、音量の変化、突発音を、音から測っています。</dd>
</dl>
<h2>寝落ち格付け</h2>
<p>{RANK_CRITERIA}</p>
<h2>寝落ちまで</h2>
<p>再生を始めてから眠るまでの分数です。Apple Watch の記録から測ります。睡眠の良し悪しは評価しません。</p>
<h2>音声の扱い</h2>
<p>解析のために一時的に音声を読み込み、終わったら消します。音声は保存も配信もしません。</p>
</section>"""


FILTER_JS = """
(()=>{const q=document.getElementById('q'),rows=[...document.querySelectorAll('#list .row')],empty=document.getElementById('empty');
const sel={rank:null,genre:null};
function apply(){const t=q.value.trim().toLowerCase();let n=0;
rows.forEach(r=>{const ok=(!t||r.dataset.q.includes(t))&&(!sel.rank||r.dataset.rank===sel.rank)&&(!sel.genre||r.dataset.genre===sel.genre);r.hidden=!ok;if(ok)n++;});
empty.hidden=n>0;}
document.querySelectorAll('.chip').forEach(c=>c.addEventListener('click',()=>{const k=c.dataset.rank?'rank':'genre',v=c.dataset[k];
sel[k]=sel[k]===v?null:v;document.querySelectorAll('.chip[data-'+k+']').forEach(o=>o.setAttribute('aria-pressed',String(o.dataset[k]===sel[k])));apply();}));
q.addEventListener('input',apply);})();
"""

DETAIL_JS = """
(()=>{const b=document.getElementById('copy');if(b)b.addEventListener('click',async()=>{const u=b.dataset.url||location.href;
try{if(navigator.share&&matchMedia('(pointer:coarse)').matches){await navigator.share({title:document.title,url:u});return;}
await navigator.clipboard.writeText(u);document.getElementById('copied').hidden=false;}catch(e){}});
document.querySelectorAll('.calm-chart').forEach(ch=>{const out=ch.querySelector('.moment-pick');
ch.querySelectorAll('.peak').forEach(p=>{const pick=()=>{ch.querySelectorAll('.peak').forEach(o=>o.classList.toggle('on',o===p));
out.innerHTML='';const m=document.createElement('b');m.textContent=p.dataset.min+'分';const s=document.createElement('span');s.textContent=p.dataset.level;
out.append(m,' '+p.dataset.note+' ',s);};p.addEventListener('click',pick);p.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();pick();}});});});})();
"""

FAVICON = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><rect width="1024" height="1024" rx="224" fill="#171C33"/>'
           '<g fill="none" stroke="#D9DCEA" stroke-width="71" stroke-linecap="round">'
           '<path d="M689.5 305.5V719" opacity=".28"/><path d="M335.5 305.5L689.5 719" opacity=".6"/><path d="M335.5 305.5V719"/></g></svg>')


def build(data: dict, out_dir: str | Path, cfg: dict, base_url: str = "") -> list[dict]:
    """サイトを out_dir に書き出す。base_url は公開先(例 https://example.com/)。OGP と共有のリンクに使う。"""
    base_url = (base_url.rstrip("/") + "/") if base_url else ""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for child in out.iterdir():  # 中身だけ消す(フォルダごと消すと、配信中のサーバーが見失う)
        shutil.rmtree(child) if child.is_dir() else child.unlink()
    shows = build_model(data, cfg)

    for f in ASSETS.iterdir():
        shutil.copy(f, out / f.name)
    (out / "favicon.svg").write_text(FAVICON, encoding="utf-8")
    og = f"{base_url}og.png" if base_url else ""
    (out / "index.html").write_text(page(title=f"{strings.PRODUCT} — {strings.TAGLINE}", desc=LEAD, root="./",
                                         body=index_html(shows), canonical=base_url, og_image=og, large_card=True),
                                    encoding="utf-8")
    (out / "about").mkdir()
    (out / "about" / "index.html").write_text(page(title=f"解析について | {strings.PRODUCT}", desc=FOOT_NOTE, root="../",
                                                   body=about_html(), canonical=base_url and base_url + "about/",
                                                   og_image=og, large_card=True), encoding="utf-8")
    for s in shows:
        d = out / "shows" / s["id"]
        d.mkdir(parents=True)
        desc = f"評点 ★ {s['show_star']:.1f}、寝落ち格付け {s['z_rank']}。{RANK_MEANING[s['z_rank']]}です。"
        d.joinpath("index.html").write_text(page(
            title=f"{s['title']} | {strings.PRODUCT}", desc=desc, root="../../", body=show_html(s, base_url, cfg),
            canonical=base_url and f"{base_url}shows/{s['id']}/", og_image=s.get("artwork_url") or og, og_type="article"),
            encoding="utf-8")

    (out / "404.html").write_text(page(title=f"{EMPTY} | {strings.PRODUCT}", desc=LEAD, root="/",
                                       body=f'<section class="hero"><h1>{EMPTY}</h1><p><a href="/">一覧へ</a></p></section>'),
                                  encoding="utf-8")
    if base_url:
        urls = [base_url, base_url + "about/"] + [f"{base_url}shows/{s['id']}/" for s in shows]
        (out / "sitemap.xml").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            + "".join(f"<url><loc>{escape(u)}</loc></url>\n" for u in urls) + "</urlset>\n", encoding="utf-8")
        (out / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {base_url}sitemap.xml\n", encoding="utf-8")
    return shows


def public_credentials() -> tuple[str, str]:
    """公開キーだけを使う。サイトは誰でも読める表しか出さないので、service key は使わない。"""
    url = os.environ.get("SUPABASE_URL") or (f"https://{os.environ['SUPABASE_HOST']}" if os.environ.get("SUPABASE_HOST") else "")
    return url, os.environ.get("SUPABASE_ANON_KEY", "")


def main(argv=None) -> int:
    """python -m neochi.site。解析の依存(numpy など)を読まずに書き出す。Vercel のビルドで使う(vercel.json)。"""
    import argparse
    import logging

    import yaml

    p = argparse.ArgumentParser(prog="neochi.site", description="紹介サイト(静的HTML)を書き出す")
    p.add_argument("--out", default="out/site")
    p.add_argument("--base-url", default=os.environ.get("SITE_URL", ""), help="公開先の URL。OGP と共有のリンクに使う")
    p.add_argument("--from-json", default=None, help="Supabase ではなく、この store.json から読む")
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if a.from_json:
        data = load_json_store(a.from_json)
    else:
        url, key = public_credentials()
        if not url or not key:
            logging.error("SUPABASE_URL(か SUPABASE_HOST)と SUPABASE_ANON_KEY を設定するか、--from-json を指定してください")
            return 1
        data = fetch_public(url, key)
    cfg = yaml.safe_load((Path(__file__).resolve().parent.parent / "config" / "scoring.yaml").read_text(encoding="utf-8"))
    shows = build(data, a.out, cfg, a.base_url)
    logging.info("サイトを書き出しました: %s(%d番組)", a.out, len(shows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
