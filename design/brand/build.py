"""ブランドアセット(ロゴ・記号・アプリアイコン)を書き出す。リポジトリの直下で `python design/brand/build.py`。

形の定義は neochi/brand.py(サイトも同じものを使う)。色と濃さは design/tokens.json の logo-bg / logo-fg / opacity-logo-1〜3。
PNG は rsvg-convert(librsvg)で書き出す。OG 画像の文字は Noto Sans CJK(なければ OG だけ作らない)。
書き出し先: design/brand/svg、design/brand/png。あわせて、アプリアイコン(ios)とサイトの画像も同じものに更新する。
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT))
from neochi import brand, strings  # noqa: E402

SVG, PNG = HERE / "svg", HERE / "png"
PNG_ICONS = [1024, 512, 192, 180, 120, 60]
IOS_ICON = ROOT / "ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SITE_ASSETS = ROOT / "neochi/site_assets"
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"

FILES = {
    # ロゴ(横組み・基本形)。地の色に合わせて選ぶ
    "wordmark-on-dark.svg": brand.wordmark(brand.FG),                    # 暗い地(基本)
    "wordmark-on-light.svg": brand.wordmark(brand.BG),                   # 明るい地
    "wordmark-mono-on-light.svg": brand.wordmark(brand.BG, mono=True),   # 1色・濃淡なし(刺繍、ハンコ、刻印)
    "wordmark-mono-on-dark.svg": brand.wordmark(brand.FG, mono=True),
    # 記号 N(背景なし)
    "symbol-on-dark.svg": brand.symbol(brand.FG),
    "symbol-on-light.svg": brand.symbol(brand.BG),
    "symbol-mono-on-light.svg": brand.symbol(brand.BG, mono=True),
    "symbol-mono-on-dark.svg": brand.symbol(brand.FG, mono=True),
    # アイコン
    "app-icon.svg": brand.icon("square"),                                # iOS。角丸なしの正方形
    "app-icon-circle.svg": brand.icon("circle"),                         # X など、丸く切り抜かれる場所
    "favicon.svg": brand.icon("square", 1024, 0.62, 0.22),               # 16px でも N の線2本が残るよう、N を大きく
}


def render(svg: Path, png: Path, width: int, height: int | None = None) -> None:
    cmd = ["rsvg-convert", str(svg), "-o", str(png), "-w", str(width)]
    if height:
        cmd += ["-h", str(height)]
    subprocess.run(cmd, check=True)


def og_image(out: Path) -> bool:
    """共有カード(1200×630)。紺の地に、ワードマークと一行の説明。"""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return False
    if not Path(FONT).exists():
        return False
    W, H = 1200, 630
    img = Image.new("RGB", (W, H), brand.BG)
    wm = PNG / "wordmark-on-dark@2x.png"
    mark = Image.open(wm).convert("RGBA")
    mw = 780
    mark = mark.resize((mw, round(mark.height * mw / mark.width)), Image.LANCZOS)
    font = ImageFont.truetype(FONT, 36, index=0)
    text = strings.TAGLINE
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=font)
    gap = 44
    top = (H - (mark.height + gap + 40)) // 2
    img.paste(mark, ((W - mw) // 2, top), mark)
    d.text(((W - tw) / 2, top + mark.height + gap), text, font=font, fill=(128, 135, 148))
    img.save(out, optimize=True)
    return True


def main() -> int:
    if not shutil.which("rsvg-convert"):
        print("rsvg-convert(librsvg)が要ります。apt install librsvg2-bin / brew install librsvg", file=sys.stderr)
        return 1
    tokens = json.loads((ROOT / "design" / "tokens.json").read_text(encoding="utf-8"))
    logo = {t["name"]: t["value"] for t in tokens["logo"]["tokens"]}
    assert (brand.BG, brand.FG) == (logo["logo-bg"], logo["logo-fg"]), "neochi/brand.py の色が design/tokens.json と違います"
    for d in (SVG, PNG):
        d.mkdir(exist_ok=True)
        for f in d.iterdir():
            f.unlink()
    for name, text in FILES.items():
        (SVG / name).write_text(text, encoding="utf-8")
    for s in PNG_ICONS:
        render(SVG / "app-icon.svg", PNG / f"app-icon-{s}.png", s, s)
    render(SVG / "app-icon-circle.svg", PNG / "x-profile-400.png", 400, 400)
    for s in (32, 16):
        render(SVG / "favicon.svg", PNG / f"favicon-{s}.png", s, s)
    for tone in ("dark", "light"):
        render(SVG / f"wordmark-on-{tone}.svg", PNG / f"wordmark-on-{tone}@2x.png", 1488)   # 透過 PNG。SVG の2倍
        render(SVG / f"symbol-on-{tone}.svg", PNG / f"symbol-on-{tone}@2x.png", 582)
    made_og = og_image(PNG / "og-1200x630.png")
    # 使う場所へ: アプリアイコン(角丸なし1024)、サイトの共有カードと apple-touch-icon
    shutil.copy(PNG / "app-icon-1024.png", IOS_ICON)
    shutil.copy(PNG / "app-icon-180.png", SITE_ASSETS / "apple-touch-icon.png")
    if made_og:
        shutil.copy(PNG / "og-1200x630.png", SITE_ASSETS / "og.png")
    print(f"svg {len(list(SVG.iterdir()))} 点、png {len(list(PNG.iterdir()))} 点を書き出しました(OG {'更新' if made_og else '未更新'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
