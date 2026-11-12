"""表示文字列の唯一の置き場。ラベルやコメントはここだけを直す。

画面とスコアカードに絵文字は使わない。眠りは Z で表す。診断に見える語は使わない(tests/test_strings.py が検査する)。
"""

PRODUCT = "neochi…"
TAGLINE = "寝落ちまでを、番組ごとに測る。"

LABEL_TOTAL = "寝落ち適性"
LABEL_INTEREST = "程よい興味"
LABEL_CALM = "起伏の少なさ"
LABEL_EAR = "耳のゆるさ"
LABEL_RESULT = "寝落ちまで"

NO_RESULT = "寝落ちまで ―"
NO_RESULT_NOTE = "寝落ちの記録を確認中です"
RESEARCHING = "調査中"

EVIDENCE = {"strong": "◎ 実証あり", "related": "◯ 関連研究あり", "hypothesis": "△ 仮説"}

# 寝落ちまでの分数 → コメント。(上限(未満), コメント) を順に見る。
_COMMENTS = [
    (5, "それは番組の力ではなく、ただの寝不足です"),
    (10, "即落ちでした"),
    (20, "理想の寝落ちでした"),
    (30, "やや粘りました"),
]
_COMMENT_LONG = "最後まで聞いてしまいました"


def sleep_comment(minutes: float) -> str:
    for upper, text in _COMMENTS:
        if minutes < upper:
            return text
    return _COMMENT_LONG


def sleep_line(minutes: int | None) -> str:
    if minutes is None:
        return f"{NO_RESULT}  {NO_RESULT_NOTE}"
    return f"本日の寝落ち、{minutes}分。{sleep_comment(minutes)}"


def divergence_reason(ai: float, crowd: float, n: int) -> str:
    """AI解析とみんなが大きくずれたときの final_reason(一行)。"""
    side = "高い" if crowd > ai else "低い"
    return f"みんな {crowd:.1f}({n}件)がAI解析 {ai:.1f}より{side}ため、両方を並べて混ぜました"
