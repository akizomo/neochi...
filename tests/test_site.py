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
        {"episode_id": "a1", "calm_star": 4.5, "ear_star": 4.0, "interest_score": 5, "content_summary": "植物の話です。"},
        {"episode_id": "b1", "ear_star": 5.0},
    ],
    "show_stats": [{"show_id": "a", "n": 4, "avg_min": 14}],
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


def test_copy_follows_voice(tmp_path):
    site.build(DATA, tmp_path, cli.load_config())
    for f in tmp_path.rglob("*.html"):
        text = re.sub(r"<script>.*?</script>", "", f.read_text(encoding="utf-8"), flags=re.S)
        text = text.replace("深夜の植物図鑑", "")
        assert not [w for w in BANNED if w in text], f
        assert "！" not in text and "…" not in text and "聞" not in text, f
        assert not re.search("[\U0001F300-\U0001FAFF]", text), f
