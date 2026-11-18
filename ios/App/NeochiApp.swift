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
    @State private var showSplash = true   // 起動時の1回だけ(SplashView)

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TonightView().tabItem { Label("今夜", systemImage: "moon") }.tag(AppModel.AppTab.tonight)
            DiscoverView().tabItem { Label("見つける", systemImage: "magnifyingglass") }.tag(AppModel.AppTab.discover)
            LogView().tabItem { Label("記録", systemImage: "clock") }.tag(AppModel.AppTab.log)
            SettingsTab().tabItem { Label("設定", systemImage: "gearshape") }.tag(AppModel.AppTab.settings)
        }
        .tint(Color.nc(.textMain))
        // 番組を読み込めるまで(Release)。読み込めなかったときは、見本の番組を出さず、やり直しを出す。
        .overlay { if model.loadState != .ready && !showSplash { LoadGateView() } }   // 起動の動きの下では出さない(透けて見えないように)
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                ToastView(text: t.text)
                    .padding(.bottom, 96)   // タブバーの上
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(t.id)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .overlay { if showSplash { SplashView { showSplash = false }.ignoresSafeArea() } }
        // 就寝時刻に開いたときと、朝の記録が開くときは、全画面の画面が上に出る。見えない裏で動かさない
        .onChange(of: model.nightScreen != nil) { _, open in if open { showSplash = false } }
        .onChange(of: model.morningOpen) { _, open in if open { showSplash = false } }
        .fullScreenCover(item: $model.nightScreen) { _ in NightView() }
        .task { await model.loadRemote() }
        .task { await model.loadHealthBedtimes() }
        .task { await model.refreshHealthAccess() }
        .onAppear { model.refreshForNewDay(); model.openNightIfBedtime(); if model.nightScreen != nil || model.morningOpen { showSplash = false } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshForNewDay(); model.openNightIfBedtime(); Task { await model.refreshHealthAccess(); await model.backfillOnsets() } } }
        .sheet(isPresented: $model.onboardingOpen) { OnboardingView().interactiveDismissDisabled() }
        // オンボーディングは、起動のアニメーションが終わってから出す。
        .onChange(of: model.needsOnboarding && !showSplash, initial: true) { _, needs in if needs { model.onboardingOpen = true } }
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
