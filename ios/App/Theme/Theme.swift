import SwiftUI
import NeochiCore
import UIKit

extension Color {
    /// デザイントークンの色。ライト/ダークは、環境の外観で切り替わる(夜の画面は dark に固定する)。
    init(_ token: NCColor) {
        self.init(uiColor: UIColor { traits in
            let c = token.rgba(traits.userInterfaceStyle == .dark ? .dark : .light)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
    }
}

extension Color {
    static func nc(_ token: NCColor) -> Color { Color(token) }
}

extension Font {
    /// 本文は Noto Sans JP、数字は JetBrains Mono(どちらも同梱が前提。なければシステムの字体にする)。
    static func nc(_ style: NCTextStyle, relativeTo: Font.TextStyle = .body) -> Font {
        let name: String
        switch style.family {
        case .mono: name = "JetBrainsMono-Medium"
        case .sans: name = style.weight >= 600 ? "NotoSansJP-Bold" : "NotoSansJP-Regular"
        }
        if UIFont(name: name, size: style.size) != nil {
            return .custom(name, size: style.size, relativeTo: relativeTo)
        }
        let weight: Font.Weight = style.weight >= 700 ? .bold : style.weight >= 600 ? .semibold : style.weight >= 500 ? .medium : .regular
        return .system(size: style.size, weight: weight, design: style.family == .mono ? .monospaced : .default)
    }
}

extension View {
    func ncText(_ style: NCTextStyle, _ color: NCColor = .textMain, relativeTo: Font.TextStyle = .body) -> some View {
        self.font(.nc(style, relativeTo: relativeTo))
            .foregroundStyle(Color(color))
            .lineSpacing(max(0, style.lineHeight - style.size * 1.2))
    }
}
