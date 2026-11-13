import SwiftUI
import NeochiCore

/// 夜の画面。ダーク固定(bg-night)。出るのは、番組名と再生/一時停止だけ。フェードは 600ms。
struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var isPlaying = true

    var body: some View {
        ZStack {
            Color.nc(.bgNight).ignoresSafeArea()
            VStack(spacing: NCSpace.s8 + NCSpace.s2) {
                Text(model.playing?.show.title ?? "").ncText(NCText.title).multilineTextAlignment(.center)
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36))
                        .frame(width: NCSize.playD, height: NCSize.playD)
                        .foregroundStyle(Color.nc(.textMain))
                        .background(Circle().fill(Color.nc(.surface)))
                        .overlay(Circle().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
                }
                .accessibilityLabel(isPlaying ? "一時停止" : "再生")
            }
            .padding(.horizontal, NCSpace.s8)
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .transition(.opacity)
        .animation(.easeInOut(duration: NCDuration.fadeNight), value: isPlaying)
    }
}
