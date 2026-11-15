"""紹介サイトの書き出し。掲載のルール(docs/SCORE.md)と、言葉の決まり(docs/VOICE.md)を守ること。"""
import re

from neochi import cli, site
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
    assert "★ 4.4" in h and "眠りたい夜は、まずこの番組" in h
    assert "AI解析・寝落ちまで 平均14分(ウォッチの実測 4件)" in h
    assert 'property="og:image" content="https://img/a.jpg"' in h
    assert 'href="https://example.com/shows/a/"' in h
    assert "https://example.com/sitemap.xml" in (tmp_path / "robots.txt").read_text()


def test_show_page_matches_app_detail(tmp_path):
    """アプリの番組の詳細と同じ並び: AI解析 → 観点ごとの根拠 → 寝落ちの実績 → 解析について。"""
    site.build(DATA, tmp_path, cli.load_config())
    h = (tmp_path / "shows" / "a" / "index.html").read_text(encoding="utf-8")
    h = h[h.index("<main"):h.index("</main>")]   # ヘッダーの「解析について」を除く
    order =["穏やかな語りの回です。", "観点ごとの根拠", "起伏の少なさ", "耳のゆるさ", "程よい興味", "寝落ちの実績", "解析について"]
    pos = [h.index(t) for t in order]
    assert pos == sorted(pos)
    assert "冒頭4分に、小さな山が1つだけです。" in h and "珍しい花の話" in h
    assert "260字/分" in h and "15%" in h and "5.0dB" in h and "1.0回/10分" in h
    assert "この回の内容(AIの要約)" in h and "程よい" in h
    assert 'aria-label="寝落ちの実績 4件"' in h and "30分未満 3件" in h
    assert "290字/分までは満点、450字で最低" in h


def test_logo_and_icons(tmp_path):
    site.build(DATA, tmp_path, cli.load_config(), "https://example.com/")
    h = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert 'class="logo-n"' in h and 'og:image" content="https://example.com/og.png"' in h
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
