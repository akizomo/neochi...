import SwiftUI
import NeochiCore

/// ボタンの種類。見た目(塗り・枠・文字の色)だけを決める。文字の大きさは変えない。
enum NCButtonKind {
    /// 主ボタン。画面でいちばん勧める操作。塗りつぶし。
    case primary
    /// 副ボタン。主ボタンの次の操作、強く勧めない操作(取り消し、あとで選ぶ)。枠線。
    case secondary
    /// 文字だけ。さらに控えめな操作(あとで、いま聴く)。
    case text
}

/// ボタンの大きさ。高さと文字(トークンの button-l / m / s)を決める。種類とは別に選ぶ。
enum NCButtonSize {
    /// 画面の主な操作。高さ 52。
    case large
    /// 主な操作の下に添える操作。高さ 44。
    case medium
    /// 行の中の短い操作。高さ 32(押せる範囲は 44 まで広げる)。
    case small

    var height: Double {
        switch self { case .large: NCSize.buttonH; case .medium: NCSize.buttonHM; case .small: NCSize.buttonHS }
    }
    var text: NCTextStyle {
        switch self { case .large: NCText.buttonL; case .medium: NCText.buttonM; case .small: NCText.buttonS }
    }
    var iconSize: Double {
        switch self { case .large: NCSize.iconMd; case .medium: NCSize.iconMd - 2; case .small: NCSize.iconSm + 1 }
    }
}

/// ボタンの見た目(ラベル)。種類 × 大きさで決まる。画面では手で組まず、これか `NCButton` を使う。
/// `selected` は、予約済みのように「押した状態」を示す(枠を濃くし、チェックを出すのは呼ぶ側のアイコンで)。
struct NCButtonLabel: View {
    let title: String
    var icon: String? = nil
    var kind: NCButtonKind = .primary
    var size: NCButtonSize = .large
    var fullWidth = true
    var selected = false

    var body: some View {
        HStack(spacing: NCSpace.s2) {
            if let icon { Image(systemName: icon).font(.system(size: size.iconSize, weight: .semibold)) }
            Text(title).lineLimit(1).minimumScaleFactor(0.85)
        }
        .ncText(size.text, foreground)
        .padding(.horizontal, size == .small ? NCSpace.s4 : NCSpace.s5)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.height)
        .background(Capsule().fill(kind == .primary ? Color.nc(.textMain) : Color.clear))
        .overlay {
            if kind == .secondary {
                Capsule().strokeBorder(selected ? Color.nc(.textMain) : Color.nc(.borderControl),
                                       lineWidth: selected ? 1.5 : NCSize.borderW)
            }
        }
        .frame(minHeight: NCSize.tapMin)          // 小さいボタンも、押せる範囲は 44 まで
        .contentShape(Rectangle())
    }

    private var foreground: NCColor {
        switch kind { case .primary: .bgBase; case .secondary: .textMain; case .text: .textSub }
    }
}

/// ボタン(押すと沈む)。`NCButtonLabel` の見た目に、操作をつけたもの。
struct NCButton: View {
    let title: String
    var icon: String? = nil
    var kind: NCButtonKind = .primary
    var size: NCButtonSize = .large
    var fullWidth = true
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NCButtonLabel(title: title, icon: icon, kind: kind, size: size, fullWidth: fullWidth, selected: selected)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 今夜聴く(主)・明日聴く(副)。番組の詳細と話の詳細で同じもの。
/// 予約したら、副ボタンの「予約済み」(枠を濃く、チェック)にし、もう一度押すと取り消す。
struct ReserveButton: View {
    let night: Int
    let reserved: Bool
    let action: () -> Void

    var body: some View {
        NCButton(title: reserved ? (night == 0 ? "今夜予約済み" : "明日予約済み") : (night == 0 ? "今夜聴く" : "明日聴く"),
                 icon: reserved ? "checkmark" : (night == 0 ? "moon" : "moon.zzz"),
                 kind: night == 0 && !reserved ? .primary : .secondary,
                 selected: reserved, action: action)
    }
}
