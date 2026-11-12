"""文言に 🥄・スプーン・診断に見える語が入っていないこと。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANNED = ["🥄", "スプーン", "不眠", "障害", "病気", "症状", "改善", "治る", "効果", "効く",
          "睡眠の質", "科学的に証明", "ゆったり", "癒し"]


def test_no_banned_words():
    files = list((ROOT / "neochi").glob("*.py")) + list((ROOT / "config").glob("*")) + [ROOT / "supabase/migrations/0001_init.sql"]
    hits = [(f.name, w) for f in files for w in BANNED if w in f.read_text(encoding="utf-8")]
    assert not hits, hits


def test_no_exclamation_in_copy():
    s = (ROOT / "neochi" / "strings.py").read_text(encoding="utf-8")
    assert "！" not in s
