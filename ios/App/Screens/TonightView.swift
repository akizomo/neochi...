import SwiftUI
import NeochiCore

/// 今夜: 昼は「決める」。見出しの右の矢印で、明日へ。予約があればその1本、なければ理由つきの3つ。
/// 決めるのは今夜と明日だけ。それより先は「次に聴く」に入れておく。
struct TonightView: View {
    @Environment(AppModel.self) private var model
    @State private var night = 0
    /// 候補カードの横スクロールで、いま先頭に見えているカード(端まで来たかを知るため)。
    @State private var cardID: String?
    /// 候補カードの横スクロールの枠(スワイプが、カードの上で始まったかを知るため)。
    @State private var carouselFrame: CGRect = .zero
    private static let space = "tonight"
    private let labels = ["今夜", "明日"]
    private let verbs = ["今夜聴く", "明日聴く"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s5) {
                    if model.morningDue { recap }
                    candidates
                    favorites
                }
                .padding(.horizontal, NCSpace.s5)
                .padding(.bottom, NCSpace.s8)
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(CarouselFrameKey.self) { carouselFrame = $0 }
                // 横にスワイプで、今夜と明日を切り替える(縦のスクロールは、そのまま動く)。
                .simultaneousGesture(DragGesture(minimumDistance: 20, coordinateSpace: .named(Self.space)).onEnded(swipe))
            }
            .refreshable { await model.refresh() }
            .background(Color.nc(.bgBase))
            .onChange(of: night) { _, _ in cardID = nil }
            .appDestinations()
            .navigationTitle(labels[night])
            .toolbarTitleDisplayMode(.inlineLarge)
            .contentMargins(.top, NCSpace.s5, for: .scrollContent)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    stepButton("arrow.left", label: "前の晩", enabled: night > 0) { night -= 1 }
                    stepButton("arrow.right", label: "次の晩", enabled: night < labels.count - 1) { night += 1 }
                }
            }

        }
    }

    /// 横のスワイプ。カードの上で始まったときは、カードを動かすのが先。カードが端まで来ているときだけ、晩を切り替える。
    private func swipe(_ v: DragGesture.Value) {
        let dx = v.translation.width, dy = v.translation.height
        guard abs(dx) > 40, abs(dx) > abs(dy) * 1.2 else { return }
        let dir = dx < 0 ? 1 : -1
        let next = night + dir
        guard labels.indices.contains(next) else { return }
        if model.reservation(night: night) == nil, carouselFrame.contains(v.startLocation) {
            let ids = model.slate(night: night).map(\.stableID)
            let current = cardID ?? ids.first
            guard current == (dir > 0 ? ids.last : ids.first) else { return }
        }
        withAnimation { night = next }
    }

    /// 矢印は常に2つ出す。行けない方向は押せなくする(標準のツールバーボタン)。
    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .disabled(!enabled)
            .accessibilityLabel(label)
    }

    private var recap: some View {
        Button { model.morningOpen = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("昨夜の結果").ncText(NCText.footnote, .textSub)
                    // 測れていない晩は「0分」と出さない(まだ答えていないだけ)。
                    if let m = model.lastNight?.minutes {
                        HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                            Text("\(m)").ncText(NCText.numMd, .accentResult)
                            Text("分").ncText(NCText.footnote, .accentResult)
                        }
                    } else {
                        Text("まだ記録していません").ncText(NCText.body)
                    }
                }
                Spacer()
                HStack(spacing: NCSpace.s1) { Text("振り返る"); Image(systemName: "chevron.right") }.ncText(NCText.footnote, .textSub)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }.buttonStyle(.pressable)
    }

    @ViewBuilder private var candidates: some View {
        if let reserved = model.reservation(night: night) {
            // 決めたあと、何が起きるかを、取り消すボタンの下に書く(押しても、どうなったか分からないので)。
            TonightCard(candidate: reserved, primaryTitle: "取り消す", primaryIcon: "xmark", secondary: true,
                        note: night == 0 ? model.reservationNote(night: 0) : "明日になると、ここが「今夜」に変わります") {
                model.cancelReservation(night: night)
            }
        } else {
            let cards = Array(model.slate(night: night).enumerated())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: NCSpace.s3) {
                    ForEach(cards, id: \.element.stableID) { _, c in
                        TonightCard(candidate: c, primaryTitle: night == 0 ? "今夜聴く" : verbs[night], primaryIcon: "moon") {
                            model.reserve(night: night, c)
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in length * 0.9 }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $cardID)
            .scrollClipDisabled()   // 影が、スクロール枠で切れないように
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .background(GeometryReader { g in
                Color.clear.preference(key: CarouselFrameKey.self, value: g.frame(in: .named(Self.space)))
            })
        }
    }

    /// お気に入りが空のとき。見つけるへ案内する。
    private var emptyFavorites: some View {
        VStack(spacing: NCSpace.s3) {
            Text("お気に入りは、まだありません。").ncText(NCText.body)
            Text("気になる番組のしおりを押すと、ここに並びます。").ncText(NCText.footnote, .textSub).multilineTextAlignment(.center)
            NCButton(title: "見つける", kind: .secondary) { model.selectedTab = .discover }
        }
        .padding(NCSpace.s5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            HStack {
                Text("お気に入り").ncText(NCText.headline)
                Spacer()
                if !model.favorites.isEmpty { Text("\(model.favorites.count)番組").ncText(NCText.footnote, .textSub) }
            }.padding(.top, NCSpace.s3)
            if model.favorites.isEmpty { emptyFavorites }
            ForEach(model.shows.filter { model.favorites.contains($0.id) }) { show in
                NavigationLink(value: show.id) {
                    ScoreRow(show: show, isFavorite: true) { model.toggleFavorite(show) }
                }.buttonStyle(.pressable)
            }
        }
    }
}

private extension Candidate {
    /// 並びが入れ替わっても、カードが同じ候補を指し続けるための識別子。
    var stableID: String { "\(show.id)/\(episode?.id ?? "-")" }
}

private struct CarouselFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
