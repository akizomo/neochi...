import SwiftUI
import NeochiCore

/// 夜の画面。ダーク固定(bg-night)。上から、番組の画像(小さく、少し暗く)・番組名・話・時間、進捗の帯、
/// 15秒戻る/再生・一時停止/15秒進む、スリープタイマーのピル。声の存在は、画像のまわりの輪で示す
/// (下に水平の波形を置くと、進捗の帯が2本あるように見えた。TestFlight のフィードバック)。
/// 進捗の帯は大きく動かすとき、15秒のボタンは聞き逃した一言に戻るとき、と役割を分ける。
/// 「寝落ちしやすいあたりへ移動」(プレミアム、docs/PREMIUM.md)は、進捗の帯の上の印と、タイマーの横のピルに置く予定。
struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var timerOpen = false

    /// 再生中はその番組。まだなら、今夜の予約、なければ今夜の先頭の候補。
    private var shown: Candidate? { model.playing ?? model.reservation(night: 0) ?? model.slate(night: 0).first }

    private var playLabel: String {
        switch model.player.state {
        case .loading: "読み込み中。押すと止めます"
        case .failed: "もう一度再生"
        default: model.player.isPlaying ? "一時停止" : "再生"
        }
    }

    /// 回の見出し。「第12回 タイトル」。番号が無い、またはタイトルにすでに回が入っているときは、タイトルだけ。
    private func episodeHeading(_ ep: Episode) -> String {
        guard let n = ep.number, !ep.title.contains("第\(n)回"), !ep.title.contains("第\(n)話"), !ep.title.contains("#\(n)") else { return ep.title }
        return "第\(n)話 \(ep.title)"
    }

    private func isCurrent(_ ep: Episode) -> Bool { model.playing?.episode?.id == ep.id && model.player.state != .idle }
    private func totalSec(_ ep: Episode) -> Double? {
        ep.durationSec.map(Double.init) ?? (isCurrent(ep) ? model.player.loadedDurationSec : nil)
    }

    /// 「12:34 / 42:10」。再生前は長さだけ。長さが分からなければ経過だけ。
    private func timeLine(_ ep: Episode) -> String? {
        let isCurrent = isCurrent(ep)
        let total = totalSec(ep)
        switch (isCurrent, total) {
        case (true, let t?): return "\(Self.clock(model.player.elapsedSec)) / \(Self.clock(t))"
        case (true, nil): return Self.clock(model.player.elapsedSec)
        case (false, let t?): return Self.clock(t)
        default: return nil
        }
    }

    private static func clock(_ sec: Double) -> String {
        let s = max(0, Int(sec.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ZStack {
            Color.nc(.bgNight).ignoresSafeArea()
            VStack(spacing: NCSpace.s8) {
                VStack(spacing: NCSpace.s2) {
                    // 何を流しているかが、ひと目で分かるように。夜なので小さく、少し暗くする。
                    if let show = shown?.show {
                        let art = UIScreen.main.bounds.height < 700 ? NCSize.artworkS : NCSize.artworkL  // 小さい画面(SE)では、操作が収まるように小さく
                        ZStack {
                            // 声の存在を、画像のまわりの細い輪で静かに示す。再生中だけ、ごくゆっくり揺れる。
                            SoftRing(playing: model.player.state == .playing, inner: art)
                            ArtworkView(show: show, size: art).opacity(0.8)
                        }
                        .padding(.bottom, NCSpace.s2)
                        .accessibilityHidden(true)
                    }
                    MarqueeText(text: shown?.show.title ?? "", style: NCText.title, centered: true)
                    if let ep = shown?.episode {
                        MarqueeText(text: episodeHeading(ep), style: NCText.body, color: .textSub, centered: true)
                        if let t = timeLine(ep) { Text(t).ncText(NCText.body, .textMain).monospacedDigit() }
                    }
                }
                .accessibilityElement(children: .combine)
                // 進捗。ドラッグで、聴き始める位置を選べる(ロック画面では動かせない)。
                // 将来、この帯の背後に「寝落ちやすさ」のグラフを重ねる(PlaybackBar の background)。
                if let ep = shown?.episode, isCurrent(ep), let total = totalSec(ep), total > 0 {
                    PlaybackBar(elapsed: model.player.elapsedSec, total: total) { model.player.seek(to: $0) }
                }
                HStack(spacing: NCSpace.s6) {
                skipButton("gobackward.15", label: "15秒戻る", by: -15)
                Button {
                    if model.playing == nil, let c = shown { model.play(c) } else { model.player.toggle() }
                } label: {
                    ZStack {
                        switch model.player.state {
                        case .loading:
                            // 読み込み中・通信待ち。止めたいときは、押せる。
                            ProgressView().controlSize(.large).tint(Color.nc(.textMain))
                        case .failed:
                            Image(systemName: "arrow.clockwise").font(.system(size: NCSize.iconPlay))
                        default:
                            Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: NCSize.iconPlay))
                        }
                    }
                    .frame(width: NCSize.playD, height: NCSize.playD)
                    .foregroundStyle(Color.nc(.textMain))
                    .background(Circle().fill(Color.nc(.surface)))
                    .overlay(Circle().strokeBorder(Color.nc(.borderControl), lineWidth: NCSize.borderW))
                }
                .accessibilityLabel(playLabel)
                skipButton("goforward.15", label: "15秒進む", by: 15)
                }
                // 失敗したときだけ、理由と次の一手を出す(ふだんは、番組名とボタンだけ)。
                if model.player.state == .failed {
                    Text("再生できませんでした。通信を確かめて、もう一度押してください")
                        .ncText(NCText.footnote, .textSub).multilineTextAlignment(.center)
                }
                Button { timerOpen = true } label: {
                    HStack(spacing: NCSpace.s2) {
                        Image(systemName: "clock")
                        if model.player.timerMinutes > 0 { Text("\(model.player.timerMinutes)分") }
                    }
                    .ncText(NCText.body, .textSub)
                    .padding(.horizontal, NCSpace.s3).frame(minWidth: NCSize.tapMin, minHeight: NCSize.tapMin)
                    .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: NCSize.borderW))
                }
                .accessibilityLabel("スリープタイマー \(model.player.timerMinutes > 0 ? "\(model.player.timerMinutes)分" : "なし")")
            }
            .padding(.horizontal, NCSpace.s8)
            VStack {
                Spacer()
                Button("終わる") { model.endPlayback() }
                    .ncText(NCText.body, .textSub).frame(minHeight: NCSize.tapMin)
            }
            .padding(.horizontal, NCSpace.s4).padding(.bottom, NCSpace.s6)
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $timerOpen) { TimerSheet().environment(model) }
    }
}

extension NightView {
    /// 15秒の送り・戻し。再生している話があるときだけ押せる。
    fileprivate func skipButton(_ icon: String, label: String, by seconds: Double) -> some View {
        let active = model.playing != nil && (model.player.state == .playing || model.player.state == .paused)
        return Button { model.player.skip(by: seconds) } label: {
            Image(systemName: icon).font(.system(size: NCSize.iconMd + NCSize.iconSm))
                .frame(width: NCSize.tapMin, height: NCSize.tapMin)
                .foregroundStyle(Color.nc(.textSub))
        }
        .disabled(!active).opacity(active ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// 番組の画像を囲む、細く柔らかな輪。夜の画面に足す表現は、これだけ(オーブや背景の光は、必要になってから)。
///
/// - 動きはごくゆっくり・ごく小さく。振幅は最大でも十数pt。
/// - 揺れの大きさは、再生中かどうかだけで決める(音量は読まない。再生の安定性に触れない)。
/// - 再生が始まると約3秒かけて現れ、止まると約8秒かけて、ほぼ静止に戻る(音のフェードと同じ長さ)。
/// - 周期の違う3つの正弦波を重ねるので、繰り返しの継ぎ目が出ない。
/// - 「視差効果を減らす」では動かさず、画面が非アクティブの間は描画を止める。
private struct SoftRing: View {
    let playing: Bool
    /// 囲む画像の一辺。輪は、その外側に描く。
    let inner: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var envelope = WaveEnvelope()

    /// 輪の半径(画像の角が収まる大きさ)と、揺れの最大の幅。
    private var radius: Double { inner * 0.76 }
    private static let maxAmp = 5.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas { ctx, size in
                envelope.advance(to: timeline.date, target: playing ? 1 : 0)
                draw(&ctx, size, envelope.value, reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: (radius + Self.maxAmp + 2) * 2, height: (radius + Self.maxAmp + 2) * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ m: Double, _ t: Double) {
        // ゆるい音量の揺らぎ(模擬)。数秒かけて行き来する。
        let n = sin(t * 0.9) * 0.5 + sin(t * 0.9 * 2.31 + 1.7) * 0.3 + sin(t * 0.9 * 4.97 + 0.4) * 0.2
        let level = 0.45 * (0.65 + 0.35 * (n + 0.5))
        let amp = (reduceMotion ? 0.0 : min(Self.maxAmp, 0.5 + level * 8)) * (0.2 + 0.8 * m)
        let c = CGPoint(x: size.width / 2, y: size.height / 2), steps = 120
        for (width, alpha, phase) in [(1.2, 0.5, 0.0), (2.6, 0.16, 0.9)] {
            var path = Path()
            for i in 0...steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                // 角度について周期が閉じるよう、整数倍の波だけを重ねる(継ぎ目が出ない)。
                let w = sin(a * 3 + t * 0.55 + phase) * 0.55 + sin(a * 5 - t * 0.8 + phase * 1.3) * 0.3 + sin(a * 8 + t * 1.1 + phase * 0.7) * 0.15
                let r = radius + w * amp
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
            ctx.stroke(path, with: .color(Color.nc(.accentResult).opacity(alpha * (0.3 + 0.7 * m))),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}

/// 揺れの大きさ(0〜1)。急に変えず、なだらかに追いかける。上がるのは約3秒、下がるのは約8秒。
private final class WaveEnvelope {
    private(set) var value = 0.0
    private var last: Date?

    func advance(to now: Date, target: Double) {
        defer { last = now }
        guard let last else { return }
        let dt = min(now.timeIntervalSince(last), 0.1)   // 長く止まったあとも、飛ばさない
        let tau = target > value ? 3.0 : 8.0
        value += (target - value) * (1 - exp(-dt / tau))
    }
}

/// スリープタイマーの選択。選んだものを塗りつぶして示す(チェックマークは使わない)。暗いシート。
struct TimerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let options = [0, 30, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            Text("スリープタイマー").ncText(NCText.headline)
            HStack(spacing: NCSpace.s2) {
                ForEach(options, id: \.self) { m in
                    let selected = model.player.timerMinutes == m
                    Button { model.player.timerMinutes = m; dismiss() } label: {
                        Text(m == 0 ? "なし" : "\(m)分").ncText(NCText.body, selected ? .bgBase : .textMain)
                            .frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
                            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(selected ? Color.nc(.textMain) : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).strokeBorder(Color.nc(.borderControl), lineWidth: selected ? 0 : NCSize.borderW))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NCSpace.s4)
        .background(Color.nc(.bgBase))
        .presentationDetents([.height(NCSize.sheetH)])
        .environment(\.colorScheme, .dark)
    }
}

/// 再生の進捗の帯。ドラッグ(またはタップ)で、その位置から聴ける。VoiceOver では ±30秒。
/// background に、位置ごとのグラフ(寝落ちやすさ)を差し込める。
private struct PlaybackBar<Background: View>: View {
    let elapsed: Double
    let total: Double
    let onSeek: (Double) -> Void
    let background: Background
    @State private var dragFraction: Double?

    init(elapsed: Double, total: Double, onSeek: @escaping (Double) -> Void, @ViewBuilder background: () -> Background = { EmptyView() }) {
        self.elapsed = elapsed; self.total = total; self.onSeek = onSeek; self.background = background()
    }

    private var fraction: Double { dragFraction ?? min(1, max(0, elapsed / total)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                background
                Capsule().fill(Color.nc(.borderControl)).frame(height: 4)
                Capsule().fill(Color.nc(.accentResult).opacity(0.8)).frame(width: max(4, w * fraction), height: 4)
                Circle().fill(Color.nc(.textMain)).frame(width: dragFraction == nil ? 10 : 16, height: dragFraction == nil ? 10 : 16)
                    .offset(x: min(max(0, w * fraction - 5), w - 10))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragFraction = min(1, max(0, $0.location.x / w)) }
                .onEnded { v in
                    onSeek(min(1, max(0, v.location.x / w)) * total)
                    dragFraction = nil
                })
        }
        .frame(height: NCSize.tapMin)
        .animation(.linear(duration: 1), value: elapsed)
        .accessibilityElement()
        .accessibilityLabel("再生位置")
        .accessibilityValue("\(Int(elapsed / 60))分 / \(Int(total / 60))分")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onSeek(min(total, elapsed + 30))
            case .decrement: onSeek(max(0, elapsed - 30))
            @unknown default: break
            }
        }
    }
}
