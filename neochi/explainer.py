"""「スコアと根拠」の説明ページ(サイトの about/)。

採点の根拠は、番組や話の画面に足さず、このページにまとめる(2026-11-16 の決定)。
中身の正は docs/EVIDENCE.md(根拠の台帳)。数値は config から読み、文章に直接書かない。
言葉の決まり(docs/VOICE.md): 診断や効能に見える語、「！」、絵文字、主語は使わない。
"""
from __future__ import annotations

from html import escape

# 出典。番号は本文の [n] と対応する。要旨(アブストラクト)で確かめた範囲だけを書く。
SOURCES = [
    ("Gross RT, Borkovec TD", "Effects of a cognitive intrusion manipulation on the sleep-onset latency of good sleepers",
     "Behavior Therapy 13:112-116, 1982", "https://pure.psu.edu/en/publications/effects-of-a-cognitive-intrusion-manipulation-on-the-sleep-onset-/"),
    ("Tang NKY, Harvey AG", "Effects of cognitive arousal and physiological arousal on sleep perception",
     "Sleep 27(1):69-78, 2004", "https://www.med.upenn.edu/cbti/assets/user-content/documents/TangandHarvey2004_EffectsofCognitiveArousalandPhysiologicArousalonSleepPerception.pdf"),
    ("Wicklow A, Espie CA", "Intrusive thoughts and their relationship to actigraphic measurement of sleep: towards a cognitive model of insomnia",
     "Behaviour Research and Therapy 38(7):679-693, 2000", "https://acnpsearch.tweb-dev.unibo.it/singlejournalindex/72876025"),
    ("Harvey AG, Payne S", "The management of unwanted pre-sleep thoughts in insomnia: distraction with imagery versus general distraction",
     "Behaviour Research and Therapy 40(3):267-277, 2002", "https://kclpure.kcl.ac.uk/portal/en/publications/the-management-of-unwanted-pre-sleep-thoughts-in-insomnia-distrac/"),
    ("Bezdek MA ほか", "Neural evidence that suspense narrows attentional focus",
     "Neuroscience, 2015", "https://control.gatech.edu/wp-content/uploads/pubs/Bezdek-et-al-2015-Neuroscience.pdf"),
    ("Basner M, McGuire S", "WHO environmental noise guidelines for the European Region: a systematic review on environmental noise and effects on sleep",
     "International Journal of Environmental Research and Public Health 15(3):519, 2018", "https://www.mdpi.com/1660-4601/15/3/519"),
    ("Ohayon M ほか", "National Sleep Foundation's sleep quality recommendations: first report",
     "Sleep Health 3(1):6-19, 2017", "https://pubmed.ncbi.nlm.nih.gov/28346153/"),
    ("Jespersen KV ほか", "Listening to music for insomnia in adults",
     "Cochrane Database of Systematic Reviews, CD010459, 2022", "https://www.cochrane.org/CD010459"),
]

INFER = "◯ 関連研究"
HYPO = "△ 仮説"


def _ref(*nums: int) -> str:
    return "".join(f'<a class="ref" href="#ref{n}">[{n}]</a>' for n in nums)


def _item(name: str, tag: str, body: str) -> str:
    cls = "tag study" if tag == INFER else "tag"
    return f'<dt>{escape(name)}<span class="{cls}">{tag}</span></dt><dd>{body}</dd>'


def _rank_lines(rank_min: dict) -> str:
    return "、".join(f"{r} {rank_min[r]:.1f}" for r in ("ZZZ", "ZZ", "Z"))


def explainer_html(cfg: dict, rank_min: dict, english: str, mark: str) -> str:
    w = cfg["total"]["weights"]
    slope = cfg["total"]["calm_slope"]
    ew = cfg["ear"]["weights"]
    rate = cfg["ear"]["rate"]["ja"]
    cv = cfg["ear"]["rate_cv"]
    vol = cfg["ear"]["volume_std_db"]
    sud = cfg["ear"]["sudden_per_10min"]
    f = cfg["final"]
    zone_lo, zone_hi = cfg["total"]["interest_zone"]["zone"]

    refs = "".join(
        f'<li id="ref{i}">{escape(a)}. {escape(t)}. {escape(j)}. <a href="{escape(u)}" rel="noopener" target="_blank">原典のページ</a></li>'
        for i, (a, t, j, u) in enumerate(SOURCES, 1))

    return f"""<section class="prose">
{mark}
<h1>スコアと根拠</h1>
<p class="en">{english}</p>

<h2>評点とは</h2>
<p>寝落ちの妨げになる要素が、少ないかどうかの推定です。眠れることの約束ではありません。</p>
<p>寝る前に聴く話の内容が、寝落ちまでの時間を縮めるかを確かめた研究は、多くありません。音楽では、自己申告の寝つきが短くなる可能性があり、機器の測定では差が見られていません{_ref(8)}。</p>
<p>寝落ちまでの分数は、Apple Watch の実測で確かめ、評点に足します。</p>

<h2>根拠の強さ</h2>
<dl>
<dt>◎ 実験の積み重ね</dt><dd>現在、該当する項目はありません。</dd>
<dt>◯ 関連研究</dt><dd>寝つきを測った研究があります。寝る前の考えごとや、夜間の騒音を調べたもので、番組を聴く場面とは条件が違います。</dd>
<dt>△ 仮説</dt><dd>寝つきを測った研究が、見つかっていません。数値は仮で、実測が集まったら見直します。</dd>
</dl>
<p>◯ の項目を重く、△ の項目を軽く扱います。</p>

<h2>3つの観点と重み</h2>
<p>起伏の少なさ {w['calm']:.1f}、程よい興味 {w['interest']:.1f}、耳のゆるさ {w['ear']:.1f}。判定のない観点は除き、重みを配り直します。</p>
<p>判定の範囲は冒頭です。寝つきは15分以内が良好とされます{_ref(7)}。内容は冒頭20分、音量と突発音は冒頭30分を見ています。</p>

<h2>起伏の少なさ</h2>
<p>冒頭20分の文字起こしを、AI が4項目で採点します。各 0〜2 点。★ は 5 − 合計 × {slope}(最低 1.0)。</p>
<dl>
{_item("感情の強さ、対立・緊張", INFER,
       f"寝る前の不安な課題で、寝つくまでが延びました{_ref(1)}。寝る前の考えごとの多さは、測定した寝つきの遅さと関係していました{_ref(3)}。")}
{_item("頭の負荷", INFER,
       f"不安でない課題でも、寝つくまでが長く感じられました{_ref(2)}。数字、固有名詞、論理の多さを見ています。")}
{_item("急な転換", HYPO, "研究は見つかっていません。")}
</dl>

<h2>程よい興味</h2>
<p>5項目を 0〜2 点で採点し、合計を引き込み力(1〜10)とします。{zone_lo}〜{zone_hi} を最良とし、外れるほど下がります。</p>
<dl>
{_item("穏やかに気をひく話", INFER,
       f"寝る前に穏やかな想像で気をそらすと、自己申告の寝つきが短くなりました{_ref(4)}。想像の課題で、番組を聴いた研究ではありません。")}
{_item("追い続ける必要", INFER, "頭の負荷と同じ考え方です。")}
{_item(f"{zone_lo}〜{zone_hi} の範囲、未解決の問い、驚き、笑い、聴き手への働きかけ", HYPO,
       f"研究に基づく値ではありません。サスペンスが注意を狭めることは、脳の研究で示されています{_ref(5)}。寝つきは測られていません。")}
</dl>

<h2>耳のゆるさ</h2>
<p>音を測った4項目を、重みを付けて合わせます。</p>
<dl>
{_item(f"突発音(重み {ew['sudden']:.1f})", INFER,
       f"直前の音より急に大きい音を数えます。{sud['best']:.0f}回/10分で満点、{sud['worst']:.0f}回で最低。最大音量が高い音ほど、目が覚める確率が上がります{_ref(6)}。眠っている間の騒音の研究です。")}
{_item(f"話す速さ(重み {ew['rate']:.1f})", HYPO,
       f"{rate['best_max']:.0f}字/分まで満点、{rate['worst']:.0f}字で最低。寝つきを測った研究は見つかっていません。")}
{_item(f"速さのばらつき(重み {ew['rate_cv']:.1f})", HYPO,
       f"揺れが {cv['best'] * 100:.0f}% 以下で満点、{cv['worst'] * 100:.0f}% で最低。寝つきを測った研究は見つかっていません。")}
{_item(f"音量の変化(重み {ew['volume']:.1f})", HYPO,
       f"{vol['best']:.0f}dB 以下で満点、{vol['worst']:.0f}dB で最低。環境騒音の研究があり、話し声に当てはまるかは不明です。編集で音量をそろえた番組ほど、小さく出ます。")}
</dl>

<h2>寝落ち格付け</h2>
<p>評点の高さだけで決めます。上位およそ15%が ZZZ、45%までが ZZ 以上、80%までが Z 以上です。</p>
<p>線は {_rank_lines(rank_min)}。基準に届かない番組は、掲載しません。</p>
<p>線は研究ではなく、NeochiPickzz の方針です。データが集まったら、割合を見直します。</p>

<h2>寝落ちまで</h2>
<p>再生を始めてから眠るまでの分数です。Apple Watch の記録から測ります。睡眠の良し悪しは評価しません。</p>
<p>評点には、{f['watch_best_min']:.0f}分以下を満点、{f['watch_worst_min']:.0f}分以上を最低として足します。寝つき15分以下が良好、60分以上は良好でない、という合意に合わせています{_ref(7)}。</p>
<p>{f['watch_min_n']}件未満は使いません。件数が増えるほど、重みが増えます(上限 {f['watch_max_weight']:.1f})。</p>

<h2>音声の扱い</h2>
<p>解析のために一時的に音声を読み込み、終わったら消します。音声は保存も配信もしません。</p>

<h2>出典</h2>
<p class="cap">各論文の要旨で確かめています。新しい研究や実測が集まったら、更新します。</p>
<ol class="refs">{refs}</ol>
</section>"""
