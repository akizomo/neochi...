import SwiftUI
import NeochiCore

/// 画面の中に置く、小さなロゴのアニメーション(起動画面と同じ動き)。
/// N が右下の角を軸に倒れて Z になり、小さい z が浮かんで消える。出たときに1回だけ動き、そのあとは Z で止まる。
/// 「視差効果を減らす」では動かさず、N を見せるだけ。色は画面の文字色(ライト・ダークで変わる)。
struct LogoAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    private let unit: CGFloat = 0.14
    private let lead = 0.4      // 出てすぐに倒れ始めないよう、起動画面の動きを先へ進めて始める

    var body: some View {
        TimelineView(.animation(paused: finished)) { context in
            let t = context.date.timeIntervalSince(start) + lead
            Canvas { ctx, size in draw(&ctx, size: size, t: t) }
        }
        .frame(width: 240, height: 230)   // 倒れる N と、浮かぶ z が、枠で切れない大きさ
        .task {
            guard !reduceMotion else { return }
            guard (try? await Task.sleep(for: .seconds(SplashTimeline.floaters.map { $0.start + $0.duration }.max()! - lead + 0.1))) != nil else { return }
            finished = true
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let k = unit
        let fg = Color.nc(.textMain)
        let pivot = CGPoint(x: size.width / 2 - 78 * k, y: size.height / 2 + 330 * k)
        var n = ctx
        n.translateBy(x: pivot.x, y: pivot.y)
        n.rotate(by: .degrees(SplashTimeline.angle(at: t, reduceMotion: reduceMotion)))
        n.scaleBy(x: k, y: k)
        n.translateBy(x: -628, y: 0)
        for band in LogoGeometry.bands {
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
