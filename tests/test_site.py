"""紹介サイトの書き出し。掲載のルール(docs/SCORE.md)と、言葉の決まり(docs/VOICE.md)を守ること。"""
import re

from neochi import cli, site, strings
from tests.test_strings import BANNED

DATA = {
    "show": [
        {"id": "a", "title": "深夜の植物図鑑", "publisher": "P", "genre": "朗読", "show_star": 4.4, "z_rank": "ZZZ",
         "listing_status": "listed", "artwork_url": "https://img/a.jpg", "link_url": "https://a", "apple_url": None},
        {"id": "b", "title": "判定待ちの番組", "genre": "朗読", "show_star": 5.0, "z_rank": "ZZZ",
         "listing_status": "listed"},
        {"id": "c", "title": "調査中の番組", "genre": "朗読", "show_star": None, "z_rank": None,
         "listing_status": "researching"},
    ],
    "episode": [
        {"id": "a1", "show_id": "a", "title": "第1回", "duration_sec": 1800, "published_at": "2026-11-01T00:00:00Z"},
        {"id": "b1", "show_id": "b", "title": "第1回"},
        {"id": "c1", "show_id": "c", "title": "第1回"},
    ],
    "analysis": [
        {"episode_id": "a1", "calm_star": 4.5, "ear_star": 4.0, "final_star": 4.4, "interest_level": "mid", "interest_score": 5,
         "input_depth": "transcript", "content_summary": "植物の話です。", "calm_per_min": [0.2, 0.5, 1.2, 0.3],
         "reasons": {"llm": "穏やかな語りの回です。", "moments": [{"min": 2, "note": "珍しい花の話", "level": 1}],
                     "items": {"calm": {"A": {"score": 0}, "B": {"score": 1, "min": 2}},
                               "interest": {"A": {"score": 1, "min": 3}, "B": {"score": 2, "min": 5}}}},
         "features": {"speech_rate": 260, "speech_rate_cv": 0.15, "volume_std_db": 5.0, "sudden_per_10min": 1.0,
                      "ear_parts": {"rate": 5.0, "rate_cv": 4.3, "volume": 4.5, "sudden": 4.6},
                      "timeline": {"rate_per_min": [250, 270, None, 260], "volume_db": [0.1, -0.5, 1.2], "sudden_at_sec": [65]}}},
        {"episode_id": "b1", "ear_star": 5.0},
    ],
    "show_stats": [{"show_id": "a", "n": 4, "avg_min": 14, "min_min": 8, "max_min": 31, "under30": 3}],
    "show_sleep_points": [{"show_id": "a", "night": "2026-11-0%d" % d, "latency_min": m} for d, m in enumerate([8, 12, 31, 14], 1)],
}


def test_only_listed_and_judged_shows(tmp_path):
    shows = site.build(DATA, tmp_path, cli.load_config(), "https://example.com")
    assert [s["id"] for s in shows] == ["a"]
    assert (tmp_path / "shows" / "a" / "index.html").exists()
    assert not (tmp_path / "shows" / "b").exists() and not (tmp_path / "shows" / "c").exists()


def test_show_page_has_breakdown_and_ogp(tmp_path):
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    h = (tmp_path / "shows" / "a" / "index.html").read_text(encoding="utf-8")
    assert "評点 4.4" in h and "★ 4.4" not in h and "眠りたい夜は、まずこの番組" in h
    assert "AI解析・寝落ちまで 平均14分(ヘルスケアの実測 4件)" in h
    assert 'property="og:image" content="https://img/a.jpg"' in h
    assert 'href="https://example.com/shows/a/"' in h
    assert "https://example.com/sitemap.xml" in (tmp_path / "robots.txt").read_text()


def test_show_page_matches_app_detail(tmp_path):
    """アプリの番組の詳細と同じ並び: 最新の話 → この番組の傾向 → 話の一覧 → 寝落ちの実績 → 解析について。
    観点ごとの根拠は、番組のページには出さない(話のページで見せる)。"""
    site.build(DATA, tmp_path, cli.load_config())
    h = (tmp_path / "shows" / "a" / "index.html").read_text(encoding="utf-8")
    h = h[h.index("<main"):h.index("</main>")]   # ヘッダーの「解析について」を除く
    order = ["最新の話", "この番組の傾向", "穏やかな語りの回です。", "起伏の少なさ", "耳のゆるさ", "程よい興味",
             "話の一覧", "寝落ちの実績", "解析について"]
    pos = [h.index(t) for t in order]
    assert pos == sorted(pos)
    assert 'href="episodes/a1/"' in h and "解析待ち" not in h
    assert "観点ごとの根拠" not in h and "珍しい花の話" not in h and "260字/分" not in h
    assert 'aria-label="寝落ちの実績 4件"' in h and "30分未満 3件" in h


def test_episode_page_has_evidence(tmp_path):
    """話のページ: 番組へ戻る → この話の評点 → AI解析 → 観点ごとの根拠 → 解析について。"""
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    h = (tmp_path / "shows" / "a" / "episodes" / "a1" / "index.html").read_text(encoding="utf-8")
    h = h[h.index("<main"):h.index("</main>")]
    order = ["深夜の植物図鑑", "この話の評点", "穏やかな語りの回です。", "観点ごとの根拠", "起伏の少なさ", "耳のゆるさ", "程よい興味", "解析について"]
    pos = [h.index(t) for t in order]
    assert pos == sorted(pos)
    assert "冒頭4分に、小さな山が1つだけです。" in h and "珍しい花の話" in h
    assert "260字/分" in h and "15%" in h and "5.0dB" in h and "1.0回/10分" in h
    assert "この話の内容(AIの要約)" in h and "290字/分までは満点、450字で最低" in h
    assert "https://example.com/shows/a/episodes/a1/" in (tmp_path / "sitemap.xml").read_text()


def test_logo_and_icons(tmp_path):
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    h = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert 'class="logo-w"' in h and 'og:image" content="https://example.com/og.png"' in h
    for f in ("og.png", "apple-touch-icon.png", "favicon.svg", "style.css"):
        assert (tmp_path / f).exists()


def test_copy_follows_voice(tmp_path):
    site.build(DATA, tmp_path, cli.load_config())
    for f in tmp_path.rglob("*.html"):
        text = re.sub(r"<script>.*?</script>", "", f.read_text(encoding="utf-8"), flags=re.S)
        text = text.replace("深夜の植物図鑑", "")
        assert not [w for w in BANNED if w in text], f
        assert "！" not in text and "…" not in text and "聞" not in text, f
        assert not re.search("[\U0001F300-\U0001FAFF]", text), f


def test_record_hidden_without_data(tmp_path):
    """寝落ちの実績は、データがない間は欄ごと出さない。ある番組には出す。"""
    site.build(DATA, tmp_path, cli.load_config())
    assert "寝落ちの実績" in (tmp_path / "shows" / "a" / "index.html").read_text(encoding="utf-8")
    empty = {**DATA, "show_stats": [], "show_sleep_points": []}
    site.build(empty, tmp_path, cli.load_config())
    h = (tmp_path / "shows" / "a" / "index.html").read_text(encoding="utf-8")
    assert "寝落ちの実績" not in h and "実測の記録はまだありません" not in h


def test_index_has_tonight_rankings_and_no_star_on_total(tmp_path):
    """トップは 今夜の1本 → 格付けの見かた → 2つのランキング。番組の総合の点に★を使わない(docs/VOICE.md)。"""
    site.build(DATA, tmp_path, cli.load_config())
    h = (tmp_path / "index.html").read_text(encoding="utf-8")
    h = h[h.index("<main"):h.index("</main>")]
    assert strings.TAGLINE in h and "寝落ち格付けの見かた" in h and "ZZ" in h
    order = ["今夜の1本", "寝落ち格付けの見かた", "寝落ち向きに作られた番組ランキング", "系統で探す"]
    pos = [h.index(t) for t in order]
    assert pos == sorted(pos)
    assert "ふだんの番組で、寝落ち向きランキング" not in h      # その種類の番組がなければ、棚ごと出さない
    assert "★" not in h and "ZZZ は4.5以上" not in h            # 基準の数字は「スコアと根拠」に置く
    assert "ZZZ 4.5" in (tmp_path / "about" / "index.html").read_text(encoding="utf-8")


def test_usual_shows_get_their_own_ranking(tmp_path):
    data = {**DATA, "show": DATA["show"] + [{"id": "d", "title": "ふだんの雑談", "genre": "雑談", "show_star": 3.7, "z_rank": "ZZ",
                                              "listing_status": "listed"}],
            "episode": DATA["episode"] + [{"id": "d1", "show_id": "d", "title": "第9回", "published_at": "2026-11-02T00:00:00Z"}],
            "analysis": DATA["analysis"] + [{"episode_id": "d1", "calm_star": 3.5, "ear_star": 3.5, "final_star": 3.7,
                                             "interest_level": "mid", "interest_score": 5, "input_depth": "transcript"}]}
    shows = site.build(data, tmp_path, cli.load_config())
    assert [site.kind_of(s) for s in shows] == ["made", "usual"]
    h = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert "ふだんの番組で、寝落ち向きランキング" in h and h.index("寝落ち向きに作られた番組ランキング") < h.index("ふだんの番組で、寝落ち向きランキング")
    assert "寝落ち向きの話" in h        # 今夜の1本と別の番組の回が、1つ以上あるとき
    r = (tmp_path / "ranking" / "index.html").read_text(encoding="utf-8")
    assert 'data-kind="usual"' in r and 'data-kind="made"' in r and 'data-rank="ZZ"' in r
    assert "ranking/" in (tmp_path / "sitemap.xml").read_text() if (tmp_path / "sitemap.xml").exists() else True


def test_tonight_picks_highest_recent_episode():
    from datetime import date
    a = {"id": "x", "scored": [({"published_at": "2026-11-10T00:00:00Z"}, {"final_star": 4.0}),
                               ({"published_at": "2026-08-01T00:00:00Z"}, {"final_star": 4.9})]}
    b = {"id": "y", "scored": [({"published_at": "2026-11-12T00:00:00Z"}, {"final_star": 4.5})]}
    top = site.episode_picks([a, b], date(2026, 11, 16))
    assert [p[0]["id"] for p in top] == ["y", "x"]                   # 30日より前の4.9は、直近に該当があるうちは選ばない
    assert site.episode_picks([a], date(2027, 6, 1))[0][2]["final_star"] == 4.9   # 直近になければ全期間から


def test_every_page_leads_further(tmp_path):
    """行き止まりを作らない: 棚・今夜の1本・格付けの見かたからランキングへ、番組ページから系統・ランキング・トップへ。"""
    site.build(DATA, tmp_path, cli.load_config())
    top = (tmp_path / "index.html").read_text(encoding="utf-8")
    for href in ('href="ranking/?kind=made"', 'href="ranking/?rank=ZZZ"', 'href="shows/a/"', 'class="pcard pcard-more"'):
        assert href in top, href
    show = (tmp_path / "shows" / "a" / "index.html").read_text(encoding="utf-8")
    for href in ('href="../../"', 'href="../../ranking/"', 'href="../../ranking/?genre=', 'href="../../#tonight"'):
        assert href in show, href
    assert 'class="foot-nav"' in show and 'href="../../ranking/"' in show


def test_episodes_page_and_links_have_arrows(tmp_path):
    """「寝落ち向きの話」には、すべて見るの行き先(/episodes/)がある。話は、話のページへつなぐ。"""
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    e = (tmp_path / "episodes" / "index.html").read_text(encoding="utf-8")
    assert 'class="ep"' in e and 'href="../shows/a/episodes/a1/"' in e and 'data-star="4.40"' in e and 'id="sort"' in e
    assert "https://example.com/episodes/" in (tmp_path / "sitemap.xml").read_text(encoding="utf-8")
    top = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert 'class="foot-nav"' in top and 'href="./episodes/"' in top
    css = (tmp_path / "style.css").read_text(encoding="utf-8")
    assert ".ep a::after" in css and ".tile::after" in css


def test_maker_and_support_links(tmp_path):
    """応援(Buy Me a Coffee)の固定ボタンは、読み物のページ(スコアと根拠・プライバシー)以外の右下に出す。フッターは「made by」の文字。「解析について」の作った人にも、リンクがある。外へのリンクは noopener。"""
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    for path in ("index.html", "about/index.html", "shows/a/index.html", "shows/a/episodes/a1/index.html"):
        h = (tmp_path / path).read_text(encoding="utf-8")
        if path == "about/index.html":   # 固定ボタンは出さない。作った人の文字リンクだけ
            assert h.count("buymeacoffee.com/akizomo") == 1 and 'class="bmc-fab"' not in h, path
        else:
            assert h.count("buymeacoffee.com/akizomo") == 1, path
            assert 'class="bmc-fab"' in h and "img.buymeacoffee.com/button-api" in h and "コーヒーで応援する" in h, path
        assert re.search(r'class="foot-brand">.*?</a><span class="foot-made">made by akihiro uezono</span>', h), path
        assert "作った人" not in h or path == "about/index.html"
    about = (tmp_path / "about" / "index.html").read_text(encoding="utf-8")
    assert "作った人" in about and "akihiro uezono" in about and 'href="https://github.com/akizomo"' in about
    for path in ("index.html", "about/index.html", "shows/a/index.html"):
        for m in re.finditer(r'<a [^>]*href="https://(?:www\.buymeacoffee\.com|github\.com)[^>]*>', (tmp_path / path).read_text(encoding="utf-8")):
            assert 'rel="noopener"' in m.group(0), m.group(0)


def test_reading_pages_have_no_support_button(tmp_path):
    """スコアと根拠・プライバシーには、本文に重なる固定の応援ボタンを出さない。"""
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    for path in ("about/index.html", "privacy.html"):
        h = (tmp_path / path).read_text(encoding="utf-8")
        assert "bmc-fab" not in h and 'class="nofab"' in h, path


def test_header_menu_stays_in_one_row_and_header_is_fixed(tmp_path):
    """ヘッダーのメニューは、細い画面でもロゴの下に1行で並べる(折り返さない)。ヘッダーは固定(sticky)。ハンバーガーは使わない。"""
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    h = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert "menu-btn" not in h and "site-nav" not in h
    css = (tmp_path / "style.css").read_text(encoding="utf-8")
    assert ".top { position: sticky; top: 0;" in css and ".top nav { display: flex; gap: 20px; white-space: nowrap; }" in css
    assert ".top nav { flex-basis: 100%;" in css


def test_ranking_pages_switch_between_shows_and_episodes(tmp_path):
    """ランキングは、番組と話を切り替えられる。今いる方が current で、もう一方へのリンクがある。"""
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    shows = (tmp_path / "ranking" / "index.html").read_text(encoding="utf-8")
    eps = (tmp_path / "episodes" / "index.html").read_text(encoding="utf-8")
    assert re.search(r'<a href="\.\./ranking/" aria-current="page">番組', shows) and 'href="../episodes/">話' in shows
    assert re.search(r'<a href="\.\./episodes/" aria-current="page">話', eps) and 'href="../ranking/">番組' in eps
    assert "<h1>ランキング</h1>" in eps and "その話のページへ移ります" in eps


def test_short_urls_and_old_urls_redirect(tmp_path):
    """URL には、UUID の先頭8文字を使う。公開済みの長い URL は、短い URL へ移す。"""
    uid, eid = "023d5b4d-8991-57ec-8f1e-5399e6b0e822", "93a7a6c6-0f6d-5d52-b356-8a0fc482d7e1"
    data = {**DATA, "show": [{**DATA["show"][0], "id": uid}, *DATA["show"][1:]],
            "episode": [{**DATA["episode"][0], "id": eid, "show_id": uid}, *DATA["episode"][1:]],
            "analysis": [{**DATA["analysis"][0], "episode_id": eid}, *DATA["analysis"][1:]],
            "show_stats": [{**DATA["show_stats"][0], "show_id": uid}],
            "show_sleep_points": [{**p, "show_id": uid} for p in DATA["show_sleep_points"]]}
    site.build(data, tmp_path, cli.load_config(), "https://example.com/")
    new = tmp_path / "shows" / "023d5b4d" / "episodes" / "93a7a6c6" / "index.html"
    assert new.exists() and (tmp_path / "shows" / "023d5b4d" / "index.html").exists()
    top = (tmp_path / "ranking" / "index.html").read_text(encoding="utf-8")
    assert 'href="../shows/023d5b4d/"' in top and uid not in top
    assert uid not in (tmp_path / "sitemap.xml").read_text() and "shows/023d5b4d/episodes/93a7a6c6/" in (tmp_path / "sitemap.xml").read_text()
    old = (tmp_path / "shows" / uid / "episodes" / eid / "index.html").read_text(encoding="utf-8")
    assert 'url=../../../023d5b4d/episodes/93a7a6c6/' in old
    assert 'url=../023d5b4d/' in (tmp_path / "shows" / uid / "index.html").read_text(encoding="utf-8")


def test_short_slugs_stay_unique():
    ids = ["aaaaaaaa-1111-0000-0000-000000000001", "aaaaaaaa-2222-0000-0000-000000000002", "bbbbbbbb-0000-0000-0000-000000000003"]
    sl = site.short_slugs(ids)
    assert len(set(sl.values())) == 3 and sl[ids[2]] == "bbbbbbbb" and len(sl[ids[0]]) > 8


def test_explainer_page_cites_every_source_and_marks_strength(tmp_path):
    """スコアと根拠のページ: 本文の [n] がすべて出典に対応し、各項目に根拠の強さ(◯ 関連研究 / △ 仮説)が付く。数値は config から出る。"""
    import re

    cfg = cli.load_config()
    site.build(DATA, tmp_path, cfg)
    h = (tmp_path / "about" / "index.html").read_text(encoding="utf-8")
    cited = set(re.findall(r'href="#ref(\d+)"', h))
    listed = set(re.findall(r'<li id="ref(\d+)">', h))
    assert cited and cited <= listed and len(listed) == 9
    items = re.findall(r"<dt>(.*?)</dt>", h)
    scored = [i for i in items if 'class="tag' in i]
    assert len(scored) >= 10 and all(("◯ 関連研究" in i) or ("△ 仮説" in i) for i in scored)
    w = cfg["total"]["weights"]
    assert f"起伏の少なさ {w['calm']:.1f}、程よい興味 {w['interest']:.1f}、耳のゆるさ {w['ear']:.1f}" in h
    assert "眠れることの約束ではありません" in h
    assert "スコアと根拠" in (tmp_path / "index.html").read_text(encoding="utf-8")


def test_brand_matches_tokens_and_exports():
    """ロゴの色と濃さは design/tokens.json と同じ。書き出したアセットが揃っている。"""
    import json
    from pathlib import Path

    from neochi import brand
    root = Path(__file__).resolve().parent.parent
    tk = json.loads((root / "design/tokens.json").read_text(encoding="utf-8"))
    logo = {t["name"]: t["value"] for t in tk["logo"]["tokens"]}
    op = {t["name"]: float(t["value"]) for t in tk["opacity"]["tokens"] if t["name"].startswith("opacity-logo")}
    assert (brand.BG, brand.FG) == (logo["logo-bg"], logo["logo-fg"])
    assert (brand.O1, brand.O2, brand.O3) == (op["opacity-logo-1"], op["opacity-logo-2"], op["opacity-logo-3"])
    for f in ("svg/wordmark-on-dark.svg", "svg/wordmark-on-light.svg", "svg/symbol-on-dark.svg", "svg/app-icon.svg", "svg/favicon.svg",
              "png/app-icon-1024.png", "png/og-1200x630.png", "png/x-profile-400.png"):
        assert (root / "design/brand" / f).exists(), f
    # 同じページにワードマークを2つ置いても、clipPath の名前が重ならない
    assert brand.wordmark("#fff", uid="a") .count('id="a0"') == 1 and 'id="b0"' in brand.wordmark("#fff", uid="b")
