import SwiftUI
import NeochiCore

/// 夜の画面。ダーク固定(bg-night)。出るのは、番組名と再生/一時停止、スリープタイマーの小さなピルだけ。
struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var timerOpen = false

    var body: some View {
        ZStack {
            Color.nc(.bgNight).ignoresSafeArea()
            VStack(spacing: NCSpace.s8) {
                Text(model.playing?.show.title ?? "").ncText(NCText.title).multilineTextAlignment(.center)
                Button { model.player.toggle() } label: {
                    Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36))
                        .frame(width: NCSize.playD, height: NCSize.playD)
                        .foregroundStyle(Color.nc(.textMain))
                        .background(Circle().fill(Color.nc(.surface)))
                        .overlay(Circle().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
                }
                .accessibilityLabel(model.player.isPlaying ? "一時停止" : "再生")
                Button { timerOpen = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        if model.player.timerMinutes > 0 { Text("\(model.player.timerMinutes)分") }
                    }
                    .ncText(NCText.body, .textSub)
                    .padding(.horizontal, NCSpace.s3).frame(minWidth: NCSize.tapMin, minHeight: NCSize.tapMin)
                    .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
                }
                .accessibilityLabel("スリープタイマー \(model.player.timerMinutes > 0 ? "\(model.player.timerMinutes)分" : "なし")")
            }
            .padding(.horizontal, NCSpace.s8)
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $timerOpen) { TimerSheet().environment(model) }
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
                            .overlay(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).strokeBorder(Color.nc(.borderControl), lineWidth: selected ? 0 : 1))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NCSpace.s4)
        .background(Color.nc(.bgBase))
        .presentationDetents([.height(160)])
        .environment(\.colorScheme, .dark)
    }
}
