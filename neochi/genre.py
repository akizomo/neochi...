"""番組の系統(画面に出す分類)。決まりは docs/VOICE.md §7。

系統はアプリ独自のもの。寝落ちに関わる系統(寝落ち用・朗読・環境音)は、Apple Podcasts にない分け方なので、手で決める。
それ以外は、配信者が RSS に書いた Apple Podcasts のカテゴリ(itunes:category)から、初期値を決める。
CSV の genre に書いた値が、いつも優先する。
"""
from __future__ import annotations

# 画面に出す系統。並びは見つけるの絞り込みの順。
GENRES = ["寝落ち用", "朗読", "環境音", "コメディ", "雑談", "教養"]

# 寝落ちのために作られた系統と、そうでない系統。見つけるの「寝落ち用の中で」と「寝落ち用ではないのに眠れる」に使う。
# 朗読・環境音は、どちらの目的の番組もあるので、どちらにも入れない。
SLEEP_MADE = {"寝落ち用"}
NOT_SLEEP_MADE = {"コメディ", "雑談", "教養"}

# Apple Podcasts の大分類 → 系統。系統を分けるときは、Apple の日本語の名前(歴史、科学、ニュースなど)を使う。
APPLE_TO_GENRE = {
    "Comedy": "コメディ",
    "Society & Culture": "雑談", "Leisure": "雑談", "Arts": "雑談", "TV & Film": "雑談", "Music": "雑談",
    "Kids & Family": "雑談", "Sports": "雑談", "True Crime": "雑談", "Religion & Spirituality": "雑談",
    "Fiction": "朗読",  # 物語の番組。朗読の初期値にする(寝落ち用・環境音は Apple からは決まらない)
    "Education": "教養", "History": "教養", "Science": "教養", "Business": "教養", "Technology": "教養",
    "Government": "教養", "News": "教養", "Health & Fitness": "教養",
}


def from_apple(apple_category: str | None) -> str:
    """Apple Podcasts のカテゴリ(「大分類>小分類」)から、系統の初期値を決める。分からなければ雑談。"""
    top = (apple_category or "").split(">")[0].strip()
    return APPLE_TO_GENRE.get(top, "雑談")


def resolve(genre: str | None, apple_category: str | None) -> str:
    """CSV に書いた系統があればそれ、なければ Apple のカテゴリから。"""
    g = (genre or "").strip()
    return g if g else from_apple(apple_category)
