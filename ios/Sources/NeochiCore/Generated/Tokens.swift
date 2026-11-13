// 自動生成: ios/Scripts/gen_tokens.py。手で書き換えない。値は design/tokens.json にある。
import Foundation

public struct NCRGBA: Hashable, Sendable {
    public let r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
}

public enum NCTheme: String, CaseIterable, Sendable { case dark, light }

public enum NCColor: String, CaseIterable, Sendable {
    case bgNight = "bg-night"
    case bgBase = "bg-base"
    case surface = "surface"
    case line = "line"
    case textMain = "text-main"
    case textSub = "text-sub"
    case accentFactor = "accent-factor"
    case accentResult = "accent-result"
    case borderControl = "border-control"
    case surfacePressed = "surface-pressed"
    case textDisabled = "text-disabled"
    case factorTint = "factor-tint"
    case resultTint = "result-tint"
    case scrim = "scrim"
    case onAccent = "on-accent"
    case focusRing = "focus-ring"

    public func rgba(_ theme: NCTheme) -> NCRGBA {
        switch (self, theme) {
        case (.bgNight, .dark): return NCRGBA(0.043137, 0.050980, 0.070588, 1.0000)
        case (.bgNight, .light): return NCRGBA(0.043137, 0.050980, 0.070588, 1.0000)
        case (.bgBase, .dark): return NCRGBA(0.070588, 0.082353, 0.109804, 1.0000)
        case (.bgBase, .light): return NCRGBA(0.913725, 0.925490, 0.945098, 1.0000)
        case (.surface, .dark): return NCRGBA(0.101961, 0.121569, 0.156863, 1.0000)
        case (.surface, .light): return NCRGBA(0.964706, 0.968627, 0.976471, 1.0000)
        case (.line, .dark): return NCRGBA(0.164706, 0.188235, 0.231373, 1.0000)
        case (.line, .light): return NCRGBA(0.827451, 0.847059, 0.878431, 1.0000)
        case (.textMain, .dark): return NCRGBA(0.784314, 0.803922, 0.839216, 1.0000)
        case (.textMain, .light): return NCRGBA(0.105882, 0.125490, 0.160784, 1.0000)
        case (.textSub, .dark): return NCRGBA(0.501961, 0.529412, 0.580392, 1.0000)
        case (.textSub, .light): return NCRGBA(0.345098, 0.376471, 0.439216, 1.0000)
        case (.accentFactor, .dark): return NCRGBA(0.878431, 0.705882, 0.352941, 1.0000)
        case (.accentFactor, .light): return NCRGBA(0.498039, 0.352941, 0.019608, 1.0000)
        case (.accentResult, .dark): return NCRGBA(0.623529, 0.717647, 0.850980, 1.0000)
        case (.accentResult, .light): return NCRGBA(0.219608, 0.360784, 0.549020, 1.0000)
        case (.borderControl, .dark): return NCRGBA(0.407843, 0.439216, 0.494118, 1.0000)
        case (.borderControl, .light): return NCRGBA(0.435294, 0.470588, 0.533333, 1.0000)
        case (.surfacePressed, .dark): return NCRGBA(0.141176, 0.160784, 0.196078, 1.0000)
        case (.surfacePressed, .light): return NCRGBA(0.913725, 0.917647, 0.929412, 1.0000)
        case (.textDisabled, .dark): return NCRGBA(0.333333, 0.360784, 0.419608, 1.0000)
        case (.textDisabled, .light): return NCRGBA(0.603922, 0.631373, 0.682353, 1.0000)
        case (.factorTint, .dark): return NCRGBA(0.878431, 0.705882, 0.352941, 0.1400)
        case (.factorTint, .light): return NCRGBA(0.498039, 0.352941, 0.019608, 0.1000)
        case (.resultTint, .dark): return NCRGBA(0.623529, 0.717647, 0.850980, 0.1400)
        case (.resultTint, .light): return NCRGBA(0.219608, 0.360784, 0.549020, 0.1200)
        case (.scrim, .dark): return NCRGBA(0.000000, 0.000000, 0.000000, 0.6000)
        case (.scrim, .light): return NCRGBA(0.000000, 0.000000, 0.000000, 0.4000)
        case (.onAccent, .dark): return NCRGBA(0.043137, 0.050980, 0.070588, 1.0000)
        case (.onAccent, .light): return NCRGBA(0.964706, 0.968627, 0.976471, 1.0000)
        case (.focusRing, .dark): return NCRGBA(0.623529, 0.717647, 0.850980, 1.0000)
        case (.focusRing, .light): return NCRGBA(0.219608, 0.360784, 0.549020, 1.0000)
        }
    }
}

public enum NCSpace {
    public static let s1: Double = 4
    public static let s2: Double = 8
    public static let s3: Double = 12
    public static let s4: Double = 16
    public static let s5: Double = 20
    public static let s6: Double = 24
    public static let s8: Double = 32
    public static let s12: Double = 48
}

public enum NCRadius {
    public static let sm: Double = 8
    public static let md: Double = 12
    public static let lg: Double = 20
    public static let full: Double = 9999
}

public enum NCSize {
    public static let tapMin: Double = 44
    public static let rowH: Double = 88
    public static let artworkS: Double = 56
    public static let artworkL: Double = 120
    public static let artworkXl: Double = 168
    public static let stockD: Double = 44
    public static let playD: Double = 96
    public static let cardW: Double = 1080
    public static let cardH: Double = 1350
    public static let buttonH: Double = 52
    public static let dividerH: Double = 22
    public static let sheetH: Double = 160
    public static let borderW: Double = 1
    public static let badgeH: Double = 24
    public static let iconMd: Double = 18
    public static let iconPlay: Double = 36
    public static let popoverW: Double = 300
}

public enum NCDuration {
    public static let press: Double = 0.12
    public static let fadeDay: Double = 0.2
    public static let fadeNight: Double = 0.6
    public static let zFloat: Double = 1.6
}

public enum NCOpacity {
    public static let logo1: Double = 1
    public static let logo2: Double = 0.88
    public static let logo3: Double = 0.76
    public static let logo4: Double = 0.64
    public static let logo5: Double = 0.52
    public static let logo6: Double = 0.4
    public static let logo7: Double = 0.28
    public static let disabled: Double = 0.4
}

public struct NCBezier: Hashable, Sendable { public let x1, y1, x2, y2: Double }
public enum NCEasing {
    public static let standard = NCBezier(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
    public static let float = NCBezier(x1: 0.2, y1: 0, x2: 0, y2: 1)
}

public enum NCFontFamily: String, Sendable { case sans, mono }
public struct NCTextStyle: Hashable, Sendable {
    public let size: Double, lineHeight: Double, weight: Int, family: NCFontFamily
}
public enum NCText {
    public static let title = NCTextStyle(size: 22, lineHeight: 30, weight: 700, family: .sans)
    public static let headline = NCTextStyle(size: 17, lineHeight: 24, weight: 600, family: .sans)
    public static let body = NCTextStyle(size: 15, lineHeight: 24, weight: 400, family: .sans)
    public static let footnote = NCTextStyle(size: 13, lineHeight: 20, weight: 400, family: .sans)
    public static let caption = NCTextStyle(size: 11, lineHeight: 16, weight: 500, family: .sans)
    public static let numHero = NCTextStyle(size: 96, lineHeight: 96, weight: 500, family: .mono)
    public static let numLg = NCTextStyle(size: 40, lineHeight: 44, weight: 500, family: .mono)
    public static let numMd = NCTextStyle(size: 24, lineHeight: 28, weight: 500, family: .mono)
    public static let numSm = NCTextStyle(size: 15, lineHeight: 20, weight: 500, family: .mono)
    public static let numXs = NCTextStyle(size: 11, lineHeight: 14, weight: 500, family: .mono)
    public static let cardMinutes = NCTextStyle(size: 320, lineHeight: 320, weight: 500, family: .mono)
    public static let cardStar = NCTextStyle(size: 144, lineHeight: 144, weight: 500, family: .mono)
    public static let cardAxis = NCTextStyle(size: 56, lineHeight: 64, weight: 500, family: .mono)
    public static let cardShow = NCTextStyle(size: 44, lineHeight: 60, weight: 700, family: .sans)
    public static let cardMeta = NCTextStyle(size: 32, lineHeight: 44, weight: 400, family: .sans)
}
