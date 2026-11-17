import SwiftUI
import NeochiCore

/// 起動画面。中央で N が右下の角を軸に倒れて Z になり、小さい z が浮かんで消える。下にワードマーク。
/// 動かすのは起動時の1回だけ。タップで飛ばせる。「視差効果を減らす」では、動かさず N を見せるだけ。
/// 形は design/brand(neochi/brand.py)と同じ。時刻から決める値は NeochiCore の SplashTimeline(テストあり)。
struct SplashView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    // design/tokens.json の logo-bg / logo-fg。画面のモードに依らず、ロゴの色で出す
    private let bg = Color(red: 0x17 / 255, green: 0x1C / 255, blue: 0x33 / 255)
    private let fg = Color(red: 0xD9 / 255, green: 0xDC / 255, blue: 0xEA / 255)
    private let unit: CGFloat = 0.2            // ロゴの1単位が何ポイントか(N の高さ 698 → 約140pt)

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            ZStack {
                Canvas { ctx, size in draw(&ctx, size: size, t: t) }
                VStack {
                    Spacer()
                    Image("SplashWordmark")
                        .resizable().scaledToFit().frame(width: 180)
                        .opacity(SplashTimeline.wordmarkOpacity(at: t))
                        .padding(.bottom, 56)
                }
            }
            .opacity(SplashTimeline.screenOpacity(at: t, reduceMotion: reduceMotion))
            .background(bg.ignoresSafeArea())      // 地は、終わりまで透けさせない(動きの内容だけが溶ける)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .task {
            guard (try? await Task.sleep(for: .seconds(SplashTimeline.duration(reduceMotion: reduceMotion)))) != nil else { return }
            onFinish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NeochiPickzz")
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let k = unit
        // 倒れる軸(N の右下の角)。倒れたあとの全体が、画面の中央に収まる位置
        let pivot = CGPoint(x: size.width / 2 - 78 * k, y: size.height / 2 + 330 * k)

        var n = ctx
        n.translateBy(x: pivot.x, y: pivot.y)
        n.rotate(by: .degrees(SplashTimeline.angle(at: t, reduceMotion: reduceMotion)))
        n.scaleBy(x: k, y: k)
        n.translateBy(x: -628, y: 0)
        for band in LogoGeometry.bands {      // 3本の線が右へ薄れる
            var layer = n
            layer.clip(to: Path(CGRect(x: band.from, y: -900, width: band.to - band.from, height: 1100)))
            layer.fill(LogoGeometry.n, with: .color(fg.opacity(band.opacity)))
        }

        for f in SplashTimeline.floaters {
            let o = SplashTimeline.opacity(f, at: t, reduceMotion: reduceMotion)
            guard o > 0 else { continue }
            var z = ctx
            z.translateBy(x: pivot.x + f.x * k, y: pivot.y + (f.y - SplashTimeline.rise(f, at: t)) * k)
            z.scaleBy(x: f.scale * k, y: f.scale * k)
            z.fill(LogoGeometry.z, with: .color(fg.opacity(o)))
        }
    }
}

/// ロゴの輪郭。座標は SVG(neochi/brand.py)と同じで、y は上が負。
enum LogoGeometry {
    static let n = polygon([(274, -386), (197, -534), (194, -534), (194, 0), (86, 0), (86, -698), (212, -698), (440, -312),
                            (517, -164), (520, -164), (520, -698), (628, -698), (628, 0), (502, 0)])
    static let z = polygon([(0, 0), (0, -88), (279, -431), (9, -431), (9, -520), (408, -520), (408, -436), (125, -89), (415, -89), (415, 0)])
    /// 左から 100% / 60% / 28%(design/tokens.json の opacity-logo-1〜3)
    static let bands: [(from: CGFloat, to: CGFloat, opacity: Double)] = [(-60, 197, 1), (197, 517, 0.6), (517, 774, 0.28)]

    private static func polygon(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }
}
