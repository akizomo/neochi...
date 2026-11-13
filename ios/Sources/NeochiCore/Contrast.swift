import Foundation

/// WCAG 2 のコントラスト比。背景の上に半透明の色を重ねるときは、先に合成する。
public enum NCContrast {
    private static func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    public static func luminance(_ c: NCRGBA) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    public static func over(_ fg: NCRGBA, _ bg: NCRGBA) -> NCRGBA {
        NCRGBA(fg.r * fg.a + bg.r * (1 - fg.a), fg.g * fg.a + bg.g * (1 - fg.a), fg.b * fg.a + bg.b * (1 - fg.a))
    }

    public static func ratio(_ a: NCRGBA, _ b: NCRGBA) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    public static func ratio(_ fg: NCColor, on bg: NCColor, _ theme: NCTheme) -> Double {
        ratio(fg.rgba(theme), over(bg.rgba(theme), NCColor.bgBase.rgba(theme)))
    }
}
