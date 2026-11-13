import SwiftUI
import NeochiCore

@main
struct NeochiApp: App {
    @State private var model = AppModel.sample()

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
        TabView {
            TonightView().tabItem { Label("今夜", systemImage: "moon") }
            DiscoverView().tabItem { Label("見つける", systemImage: "magnifyingglass") }
            LogView().tabItem { Label("記録", systemImage: "clock") }
        }
        .tint(Color.nc(.textMain))
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
        .fullScreenCover(isPresented: $model.morningOpen) { MorningView() }
    }
}
