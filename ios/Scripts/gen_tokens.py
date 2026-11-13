#!/usr/bin/env python3
"""design/tokens.json から Sources/NeochiCore/Generated/Tokens.swift を生成する。

手で書き換えない。値を変えるときは design/tokens.json を直して、このスクリプトを実行する。
    python3 ios/Scripts/gen_tokens.py
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "design" / "tokens.json"
OUT = ROOT / "ios" / "Sources" / "NeochiCore" / "Generated" / "Tokens.swift"


def camel(name: str, strip: str = "", digit: str = "_") -> str:
    if strip and name.startswith(strip):
        name = name[len(strip):]
    parts = re.split(r"[-_.]", name)
    out = parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    return (digit + out) if out[:1].isdigit() else out


def parse_color(v: str):
    v = v.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?", v)
    if m:
        h = m.group(1)
        a = int(m.group(2), 16) / 255 if m.group(2) else 1.0
        return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (a,)
    m = re.fullmatch(r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)", v)
    if m:
        r, g, b = (float(m.group(i)) / 255 for i in (1, 2, 3))
        return (r, g, b, float(m.group(4)) if m.group(4) else 1.0)
    sys.exit(f"色を読めません: {v}")


def px(v: str) -> float:
    return float(v.replace("px", "").replace("ms", ""))


def main():
    t = json.loads(SRC.read_text(encoding="utf-8"))
    themes = [x["id"] for x in t["color"]["themes"]]
    first = themes[0]
    colors = {c["name"]: c["value"] for c in t["color"]["tokens"]}

    def resolve(name: str, theme: str, depth: int = 0):
        if depth > 16:
            sys.exit(f"別名が深すぎます: {name}")
        v = colors[name]
        v = v if isinstance(v, str) else v.get(theme, v[first])
        m = re.fullmatch(r"\{(.+)\}", v.strip())
        return resolve(m.group(1), theme, depth + 1) if m else parse_color(v)

    L = []
    w = L.append
    w("// 自動生成: ios/Scripts/gen_tokens.py。手で書き換えない。値は design/tokens.json にある。")
    w("import Foundation\n")
    w("public struct NCRGBA: Hashable, Sendable {")
    w("    public let r: Double, g: Double, b: Double, a: Double")
    w("    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }")
    w("}\n")
    w("public enum NCTheme: String, CaseIterable, Sendable { case " + ", case ".join(themes).replace(", case ", ", ") + " }\n")
    w("public enum NCColor: String, CaseIterable, Sendable {")
    for n in colors:
        w(f"    case {camel(n)} = \"{n}\"")
    w("\n    public func rgba(_ theme: NCTheme) -> NCRGBA {")
    w("        switch (self, theme) {")
    for n in colors:
        for th in themes:
            r, g, b, a = resolve(n, th)
            w(f"        case (.{camel(n)}, .{th}): return NCRGBA({r:.6f}, {g:.6f}, {b:.6f}, {a:.4f})")
    w("        }")
    w("    }")
    w("}\n")

    def numeric_enum(title, key, strip="", unit=1.0, digit="_"):
        w(f"public enum {title} {{")
        for x in t[key]["tokens"]:
            v = px(x["value"]) * unit
            w(f"    public static let {camel(x['name'], strip, digit)}: Double = {v:g}")
        w("}\n")

    numeric_enum("NCSpace", "spacing", "space-", digit="s")
    numeric_enum("NCRadius", "radius", "radius-")
    numeric_enum("NCSize", "size")
    numeric_enum("NCDuration", "duration", "duration-", 0.001)  # 秒
    w("public enum NCOpacity {")
    for x in t["opacity"]["tokens"]:
        w(f"    public static let {camel(x['name'], 'opacity-')}: Double = {float(x['value']):g}")
    w("}\n")
    w("public struct NCBezier: Hashable, Sendable { public let x1, y1, x2, y2: Double }")
    w("public enum NCEasing {")
    for x in t["easing"]["tokens"]:
        m = re.fullmatch(r"cubic-bezier\(([^)]+)\)", x["value"])
        a = [float(s) for s in m.group(1).split(",")]
        w(f"    public static let {camel(x['name'], 'easing-')} = NCBezier(x1: {a[0]:g}, y1: {a[1]:g}, x2: {a[2]:g}, y2: {a[3]:g})")
    w("}\n")

    w("public enum NCFontFamily: String, Sendable { case sans, mono }")
    w("public struct NCTextStyle: Hashable, Sendable {")
    w("    public let size: Double, lineHeight: Double, weight: Int, family: NCFontFamily")
    w("}")
    w("public enum NCText {")
    for g in t["type"]["groups"]:
        for s in g["styles"]:
            fam = s.get("family", g["family"])
            w(f"    public static let {camel(s['name'])} = NCTextStyle(size: {px(s['fontSize']):g}, lineHeight: {px(s['lineHeight']):g}, weight: {int(s['fontWeight'])}, family: .{fam})")
    w("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"生成: {OUT.relative_to(ROOT)} (色 {len(colors)}, 行 {len(L)})")


main()
