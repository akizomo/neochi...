import SwiftUI
import NeochiCore

@main
struct NeochiApp: App {
    @State private var model = AppModel.launch()

    init() { ArtworkLoader.configure() }

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TonightView().tabItem { Label("今夜", systemImage: "moon") }.tag(AppModel.AppTab.tonight)
            DiscoverView().tabItem { Label("見つける", systemImage: "magnifyingglass") }.tag(AppModel.AppTab.discover)
            LogView().tabItem { Label("自分", systemImage: "person.crop.circle") }.tag(AppModel.AppTab.me)
        }
        .tint(Color.nc(.textMain))
        // 番組を読み込めるまで(Release)。読み込めなかったときは、見本の番組を出さず、やり直しを出す。
        .overlay { if model.loadState != .ready { LoadGateView() } }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                ToastView(text: t.text)
                    .padding(.bottom, 96)   // タブバーの上
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(t.id)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .fullScreenCover(item: $model.nightScreen) { _ in NightView() }
        .task { await model.loadRemote() }
        .task { await model.loadHealthBedtimes() }
        .onAppear { model.openNightIfBedtime() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.openNightIfBedtime() } }
        .sheet(isPresented: Binding(get: { model.needsBedtimeQuestion }, set: { _ in })) { BedtimeSetupView().interactiveDismissDisabled() }
        .sheet(isPresented: Binding(get: { model.needsGenreQuestion }, set: { _ in })) { GenrePreferenceView().interactiveDismissDisabled() }
        .fullScreenCover(isPresented: $model.morningOpen) { MorningView() }
    }
}

/// 番組を読み込む前と、読み込めなかったときの画面。
struct LoadGateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.nc(.bgBase).ignoresSafeArea()
            if model.loadState == .failed {
                VStack(spacing: NCSpace.s4) {
                    Text("番組を読み込めませんでした").ncText(NCText.headline)
                    Text("通信を確かめて、もう一度お試しください。").ncText(NCText.footnote, .textSub)
                    Button { Task { await model.reload() } } label: {
                        Text("もう一度").ncText(NCText.headline, .bgBase)
                            .padding(.horizontal, NCSpace.s6).frame(minHeight: NCSize.buttonH)
                            .background(Capsule().fill(Color.nc(.textMain)))
                    }
                    .buttonStyle(.pressable)
                }
                .multilineTextAlignment(.center)
                .padding(NCSpace.s6)
            } else {
                ProgressView().controlSize(.large).accessibilityLabel("読み込み中")
            }
        }
    }
}
