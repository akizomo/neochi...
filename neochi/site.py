"""紹介サイト(静的HTML)を書き出す。掲載中の番組を、一覧と番組ごとのページで見せる。

データは公開キー(anon)で読める表だけを使う: show / episode / analysis / show_stats。
書き出し先は out/site/。サーバーは要らず、そのまま静的ホスティングに置ける。
言葉の決まりは docs/VOICE.md、用語は docs/SCORE.md に合わせる(絵文字・「！」を使わない、「聴く」、番組/回)。
"""
from __future__ import annotations

import json
import os
import shutil
import urllib.parse
import urllib.request
from datetime import datetime
from html import escape
from pathlib import Path
from statistics import mean

from . import strings
from .scoring import interest_star, is_judged

RANK_ORDER = {"ZZZ": 3, "ZZ": 2, "Z": 1}
# 格付けのひとこと(ios/Sources/NeochiCore/Strings.swift の rankMeaning と同じ)
RANK_MEANING = {"ZZZ": "眠りたい夜は、まずこの番組", "ZZ": "寝落ちのために選びたい番組", "Z": "寝落ちに向いた番組"}
# 格付けの線(config/z_rank.yaml と同じ値)
RANK_MIN = {"Z": 3.0, "ZZ": 3.6, "ZZZ": 4.2}

LEAD = "寝落ちに向いたポッドキャストを、評点と格付けで紹介しています。"
ENGLISH = "Neochi (n.) — Japanese for drifting off mid-episode. NeochiPickzz picks what to drift off to."
FOOT_NOTE = "評点は推定です。睡眠の良し悪しは評価していません。"
FOOT_RIGHTS = "番組名とカバー画像の権利は、各配信元にあります。音声は配信元で聴けます。"
EMPTY = "まだ掲載していません"


# ---------- データ ----------

def fetch_public(url: str, key: str) -> dict:
    """公開キーで、サイトに出す表を読む。"""
    base = url.rstrip("/") + "/rest/v1/"

    def get(path: str, select: str, extra: dict | None = None) -> list[dict]:
        q = {"select": select, **(extra or {})}
        req = urllib.request.Request(base + path + "?" + urllib.parse.urlencode(q),
                                     headers={"apikey": key, "Authorization": f"Bearer {key}"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)

    return {
        "show": get("show", "id,title,publisher,genre,show_star,z_rank,listing_status,artwork_url,link_url,apple_url"),
        "episode": get("episode", "id,show_id,title,duration_sec,published_at,link_url",
                       {"order": "published_at.desc"}),
        "analysis": get("analysis", "episode_id,calm_star,ear_star,interest_score,interest_level,content_summary"),
        "show_stats": get("show_stats", "show_id,n,avg_min"),
    }


def load_json_store(path: str | Path) -> dict:
    """data/store.json(Supabase 未設定時の保存先)から読む。"""
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    return {t: list(v.values()) if isinstance(v, dict) else v for t, v in raw.items()}


def build_model(data: dict, cfg: dict) -> list[dict]:
    """掲載中で格付けのある番組だけを、評点の高い順に返す。基準未満の番組は出さない(docs/SCORE.md)。"""
    eps_by_show: dict[str, list[dict]] = {}
    for e in data.get("episode", []):
        eps_by_show.setdefault(e["show_id"], []).append(e)
    an = {a["episode_id"]: a for a in data.get("analysis", [])}
    stats = {s["show_id"]: s for s in data.get("show_stats", [])}

    shows = []
    for s in data.get("show", []):
        if s.get("listing_status") != "listed" or s.get("z_rank") not in RANK_ORDER or s.get("show_star") is None:
            continue
        eps = sorted(eps_by_show.get(s["id"], []), key=lambda e: e.get("published_at") or "", reverse=True)
        judged = [an[e["id"]] for e in eps if e["id"] in an and is_judged(an[e["id"]])]
        if not judged:
            # 判定済みの回がない番組は掲載しない(docs/SCORE.md §1)。DB の格付けが古いままでも、サイトには出さない。
            continue
        ears = [float(an[e["id"]]["ear_star"]) for e in eps if e["id"] in an and an[e["id"]].get("ear_star") is not None]

        def interest(a: dict) -> float | None:
            if a.get("interest_score") is not None:
                return interest_star(float(a["interest_score"]), cfg)
            lv = a.get("interest_level")
            return cfg["total"]["interest_star"].get(lv) if lv else None

        ints = [v for v in (interest(a) for a in judged) if v is not None]
        calms = [float(a["calm_star"]) for a in judged]
        st = stats.get(s["id"]) or {}
        episodes = []
        for e in eps[:6]:
            a = an.get(e["id"]) or {}
            episodes.append({**e, "summary": a.get("content_summary")})
        shows.append({
            **s,
            "show_star": float(s["show_star"]),
            "axes": {
                strings.LABEL_INTEREST: round(mean(ints), 1) if ints else None,
                strings.LABEL_CALM: round(mean(calms), 1) if calms else None,
                strings.LABEL_EAR: round(mean(ears), 1) if ears else None,
            },
            "judged_n": len(judged),
            "watch_n": int(st.get("n") or 0),
            "watch_avg": st.get("avg_min"),
            "episodes": episodes,
        })
    shows.sort(key=lambda s: (-s["show_star"], -RANK_ORDER[s["z_rank"]], s["title"]))
    return shows


# ---------- 表示の部品 ----------

def breakdown(s: dict) -> str:
    """評点の内訳。あるものだけ並べる(Strings.swift の ratingBreakdown と同じ)。"""
    if s["watch_n"] >= 3 and s["watch_avg"] is not None:
        return f"AI解析・寝落ちまで 平均{s['watch_avg']}分(ウォッチの実測 {s['watch_n']}件)"
    return "AI解析"


def fmt_date(iso: str | None) -> str:
    if not iso:
        return ""
    try:
        d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return ""
    return f"{d.year}年{d.month}月{d.day}日"


def fmt_duration(sec: int | None) -> str:
    return f"{round(sec / 60)}分" if sec else ""


def badge(rank: str) -> str:
    return f'<span class="badge" aria-label="寝落ち格付け {rank}">{rank}</span>'


def artwork(url: str | None, title: str, cls: str) -> str:
    if not url:
        return f'<div class="art {cls} art-empty" aria-hidden="true">Z</div>'
    return f'<img class="art {cls}" src="{escape(url)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer">'


LOGO = ('<a class="logo" href="{root}" aria-label="NeochiPickzz">'
        'NeochiPick<span class="z1">z</span><span class="z2">z</span></a>')


def page(*, title: str, desc: str, root: str, body: str, canonical: str = "", og_image: str = "",
         og_type: str = "website") -> str:
    meta = [
        f'<meta name="description" content="{escape(desc)}">',
        f'<meta property="og:title" content="{escape(title)}">',
        f'<meta property="og:description" content="{escape(desc)}">',
        f'<meta property="og:type" content="{og_type}">',
        '<meta property="og:site_name" content="NeochiPickzz">',
        '<meta property="og:locale" content="ja_JP">',
        f'<meta name="twitter:card" content="{"summary" if og_image else "summary"}">',
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
<meta name="theme-color" content="#12151C">
<link rel="icon" href="{root}favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{root}style.css">
</head>
<body>
<header class="top"><div class="wrap">{LOGO.format(root=root)}<nav><a href="{root}about/">解析について</a></nav></div></header>
<main class="wrap">
{body}
</main>
<footer class="foot"><div class="wrap">
<p>{FOOT_NOTE}</p>
<p>{FOOT_RIGHTS}</p>
<p class="sub">{strings.PRODUCT}</p>
</div></footer>
</body>
</html>
"""


# ---------- ページ ----------

def index_html(shows: list[dict]) -> str:
    genres = sorted({s["genre"] for s in shows if s.get("genre")}, key=lambda g: -sum(1 for s in shows if s.get("genre") == g))
    rows = []
    for s in shows:
        search = f"{s['title']} {s.get('publisher') or ''} {s.get('genre') or ''}".lower()
        rows.append(f"""<li class="row" data-rank="{s['z_rank']}" data-genre="{escape(s.get('genre') or '')}" data-q="{escape(search)}">
<a href="shows/{s['id']}/">
<span class="art-wrap">{artwork(s.get('artwork_url'), s['title'], 'art-s')}{badge(s['z_rank'])}</span>
<span class="row-text"><span class="row-title">{escape(s['title'])}</span>
<span class="row-sub">{escape(s.get('genre') or '')}{' · ' + escape(s['publisher']) if s.get('publisher') else ''}</span></span>
<span class="star" aria-label="評点 {s['show_star']:.1f}">★ {s['show_star']:.1f}</span>
</a></li>""")
    chips = "".join(f'<button type="button" class="chip" data-genre="{escape(g)}" aria-pressed="false">{escape(g)}</button>' for g in genres)
    ranks = "".join(f'<button type="button" class="chip" data-rank="{r}" aria-pressed="false">{r}</button>' for r in ("ZZZ", "ZZ", "Z"))
    body = f"""<section class="hero">
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
    return body


def show_html(s: dict, base_url: str) -> str:
    axes = []
    for name, v in s["axes"].items():
        val = f"★ {v:.1f}" if v is not None else "判定待ち"
        width = f"{(v - 1) / 4 * 100:.0f}" if v is not None else "0"
        axes.append(f"""<li><span class="axis-name">{name}</span>
<span class="gauge" aria-hidden="true"><span style="width:{width}%"></span></span>
<span class="axis-val{' muted' if v is None else ''}">{val}</span></li>""")
    eps = []
    for e in s["episodes"]:
        meta = " · ".join(x for x in (fmt_date(e.get("published_at")), fmt_duration(e.get("duration_sec"))) if x)
        title = escape(e.get("title") or "")
        if e.get("link_url"):
            title = f'<a href="{escape(e["link_url"])}" rel="noopener" target="_blank">{title}</a>'
        summary = f'<p class="ep-sum">{escape(e["summary"])}</p>' if e.get("summary") else ""
        eps.append(f'<li><p class="ep-title">{title}</p><p class="ep-meta">{meta}</p>{summary}</li>')
    links = []
    if s.get("apple_url"):
        links.append(f'<a class="btn" href="{escape(s["apple_url"])}" rel="noopener" target="_blank">Apple Podcasts で聴く</a>')
    if s.get("link_url"):
        links.append(f'<a class="btn" href="{escape(s["link_url"])}" rel="noopener" target="_blank">配信元で聴く</a>')
    url = f"{base_url}shows/{s['id']}/" if base_url else ""
    share_text = f"{s['title']}。評点 ★ {s['show_star']:.1f}、寝落ち格付け {s['z_rank']}。"
    x_url = "https://x.com/intent/post?" + urllib.parse.urlencode({"text": share_text, "url": url} if url else {"text": share_text})
    summary_head = '<h2>最近の回</h2><p class="note">回の内容は、AIの要約です。</p>' if any(e.get("summary") for e in s["episodes"]) else "<h2>最近の回</h2>"
    return f"""<p class="back"><a href="../../">一覧へ</a></p>
<section class="detail-head">
{artwork(s.get('artwork_url'), s['title'], 'art-l')}
<div>
<p class="rank-line">{badge(s['z_rank'])}<span class="rank-meaning">{RANK_MEANING[s['z_rank']]}</span></p>
<h1>{escape(s['title'])}</h1>
<p class="sub">{escape(s.get('genre') or '')}{' · ' + escape(s['publisher']) if s.get('publisher') else ''}</p>
</div>
</section>
<section class="card score">
<p class="big-star" aria-label="評点 {s['show_star']:.1f}">★ {s['show_star']:.1f}</p>
<p class="sub">{breakdown(s)}</p>
<ul class="axes">{''.join(axes)}</ul>
<p class="note">判定済みの回 {s['judged_n']}回の平均です。</p>
</section>
<section class="actions">{''.join(links)}</section>
<section class="share" aria-label="共有">
<a class="btn btn-ghost" href="{escape(x_url)}" rel="noopener" target="_blank">X で共有</a>
<button type="button" class="btn btn-ghost" id="copy" data-url="{escape(url)}">リンクをコピー</button>
<span class="sub" id="copied" hidden>コピーしました</span>
</section>
<section class="episodes">{summary_head}<ul>{''.join(eps)}</ul></section>
<script>{SHARE_JS}</script>"""


def about_html() -> str:
    crit = "、".join(f"{r} は{RANK_MIN[r]:.1f}以上" for r in ("Z", "ZZ", "ZZZ"))
    return f"""<section class="prose">
<h1>解析について</h1>
<p class="en">{ENGLISH}</p>
<h2>評点</h2>
<p>番組が寝落ちに向いた作りかを、1.0〜5.0の★で表します。3つの観点を合わせた点です。</p>
<dl>
<dt>{strings.LABEL_INTEREST}</dt><dd>少し気になるが、追わなくても困らないくらいが、いちばん高くなります。冒頭を文字起こしして判定しています。</dd>
<dt>{strings.LABEL_CALM}</dt><dd>盛り上がり、驚き、対立、急な話題の転換が少ないほど、高くなります。</dd>
<dt>{strings.LABEL_EAR}</dt><dd>話す速さ、速さのばらつき、音量の変化、突発音を、音から測っています。</dd>
</dl>
<p>評点は、AI解析を土台に、ウォッチの実測とみんなの評価が集まるほど、それらを足したものです。</p>
<h2>寝落ち格付け</h2>
<p>番組の評点で決めます。{crit}です。基準に届かない番組は、掲載しません。</p>
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

SHARE_JS = """
(()=>{const b=document.getElementById('copy');if(!b)return;b.addEventListener('click',async()=>{const u=b.dataset.url||location.href;
try{if(navigator.share&&matchMedia('(pointer:coarse)').matches){await navigator.share({title:document.title,url:u});return;}
await navigator.clipboard.writeText(u);document.getElementById('copied').hidden=false;}catch(e){}});})();
"""

FAVICON = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#171C33"/>'
           '<text x="32" y="45" text-anchor="middle" font-family="system-ui,sans-serif" font-weight="700" font-size="36" '
           'fill="#D9DCEA">Z</text></svg>')


def build(data: dict, out_dir: str | Path, cfg: dict, base_url: str = "") -> list[dict]:
    """サイトを out_dir に書き出す。base_url は公開先(例 https://example.com/)。OGP と共有のリンクに使う。"""
    base_url = (base_url.rstrip("/") + "/") if base_url else ""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for child in out.iterdir():  # 中身だけ消す(フォルダごと消すと、配信中のサーバーが見失う)
        shutil.rmtree(child) if child.is_dir() else child.unlink()
    shows = build_model(data, cfg)

    (out / "style.css").write_text(CSS_PATH.read_text(encoding="utf-8"), encoding="utf-8")
    (out / "favicon.svg").write_text(FAVICON, encoding="utf-8")
    title = f"{strings.PRODUCT} — {strings.TAGLINE}"
    (out / "index.html").write_text(page(title=title, desc=LEAD, root="./", body=index_html(shows),
                                         canonical=base_url), encoding="utf-8")
    (out / "about").mkdir()
    (out / "about" / "index.html").write_text(page(title=f"解析について | {strings.PRODUCT}", desc=FOOT_NOTE, root="../",
                                                   body=about_html(), canonical=base_url and base_url + "about/"),
                                              encoding="utf-8")
    for s in shows:
        d = out / "shows" / s["id"]
        d.mkdir(parents=True)
        desc = f"評点 ★ {s['show_star']:.1f}、寝落ち格付け {s['z_rank']}。{RANK_MEANING[s['z_rank']]}です。"
        d.joinpath("index.html").write_text(page(
            title=f"{s['title']} | {strings.PRODUCT}", desc=desc, root="../../", body=show_html(s, base_url),
            canonical=base_url and f"{base_url}shows/{s['id']}/", og_image=s.get("artwork_url") or "", og_type="article"),
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


CSS_PATH = Path(__file__).resolve().parent / "site.css"


def public_credentials() -> tuple[str, str]:
    """公開キーだけを使う。サイトは誰でも読める表しか出さないので、service key は使わない。"""
    url = os.environ.get("SUPABASE_URL") or (f"https://{os.environ['SUPABASE_HOST']}" if os.environ.get("SUPABASE_HOST") else "")
    return url, os.environ.get("SUPABASE_ANON_KEY", "")
