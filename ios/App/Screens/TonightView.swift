import SwiftUI
import NeochiCore

/// 今夜: 昼は「決める」。見出しの右の矢印で、明日へ。予約があればその1本、なければ理由つきの3つ。
/// 決めるのは今夜と明日だけ。それより先は「次に聴く」に入れておく。
struct TonightView: View {
    @Environment(AppModel.self) private var model
    @State private var night = 0
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
            }
            .refreshable { await model.refresh() }
            .background(Color.nc(.bgBase))
            // 横にスワイプでも晩を切り替える。候補カードの横スクロールの上では、カードが先に動く。
            .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                let next = night + (dx < 0 ? 1 : -1)
                if labels.indices.contains(next) { withAnimation { night = next } }
            })
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
            .settingsEntry()
        }
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
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text("\(model.lastNight?.minutes ?? 0)").ncText(NCText.numMd, .accentResult)
                        Text("分").ncText(NCText.footnote, .accentResult)
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
            TonightCard(candidate: reserved, primaryTitle: "取り消す", primaryIcon: "xmark") {
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
            .scrollClipDisabled()   // 影が、スクロール枠で切れないように
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    /// お気に入りが空のとき。見つけるへ案内する。
    private var emptyFavorites: some View {
        VStack(spacing: NCSpace.s3) {
            Text("お気に入りは、まだありません。").ncText(NCText.body)
            Text("気になる番組のしおりを押すと、ここに並びます。").ncText(NCText.footnote, .textSub).multilineTextAlignment(.center)
            Button { model.selectedTab = .discover } label: {
                Text("見つけるで探す").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            .buttonStyle(.pressable)
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
