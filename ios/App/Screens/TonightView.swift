import SwiftUI
import NeochiCore

/// 今夜: 昼は「決める」。見出しの右の矢印で、明日・土曜へ。予約があればその1本、なければ理由つきの3つ。
struct TonightView: View {
    @Environment(AppModel.self) private var model
    @State private var night = 0
    private let labels = ["今夜", "明日", "土曜"]
    private let verbs = ["今夜聴く", "明日聴く", "土曜に聴く"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s3) {
                    header
                    if model.pendingMorning { recap }
                    candidates
                    favorites
                }
                .padding(.horizontal, NCSpace.s4)
                .padding(.bottom, NCSpace.s8)
            }
            .background(Color.nc(.bgBase))
            .navigationDestination(for: String.self) { DetailView(showID: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack {
            Text(labels[night]).ncText(NCText.title)
            Spacer()
            HStack(spacing: NCSpace.s2) {
                stepButton("arrow.left", label: "前の晩", enabled: night > 0) { night -= 1 }
                stepButton("arrow.right", label: "次の晩", enabled: night < labels.count - 1) { night += 1 }
            }
        }
        .frame(minHeight: NCSize.tapMin)
    }

    /// 矢印は常に2つ出す。行けない方向は押せなくして薄くする(位置が動かない)。枠線は付けない。
    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                .frame(width: NCSize.tapMin, height: NCSize.tapMin)
                .foregroundStyle(Color.nc(.textMain))
                .opacity(enabled ? 1 : 0.3)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var recap: some View {
        Button { model.morningOpen = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("昨夜の結果").ncText(NCText.footnote, .textSub)
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text("\(model.lastNight?.minutes ?? 0)").ncText(NCText.numMd, .accentResult)
                        Text("分").ncText(NCText.footnote, .accentResult)
                    }
                }
                Spacer()
                HStack(spacing: 4) { Text("振り返る"); Image(systemName: "chevron.right") }.ncText(NCText.footnote, .textSub)
            }
            .padding(.horizontal, NCSpace.s4).frame(minHeight: 72)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var candidates: some View {
        if let reserved = model.reservations[night] {
            TonightCard(candidate: reserved, primaryTitle: "取り消す", primaryIcon: "xmark") {
                model.cancelReservation(night: night)
            }
        } else {
            let cards = Array(model.slate(night: night).enumerated())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: NCSpace.s3) {
                    ForEach(cards, id: \.offset) { _, c in
                        TonightCard(candidate: c, primaryTitle: night == 0 ? "今夜聴く" : verbs[night], primaryIcon: "moon") {
                            model.reserve(night: night, c)
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in length * 0.9 }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            HStack {
                Text("お気に入り").ncText(NCText.headline)
                Spacer()
                Text("\(model.favorites.count)番組").ncText(NCText.footnote, .textSub)
            }.padding(.top, NCSpace.s3)
            ForEach(model.shows.filter { model.favorites.contains($0.id) }) { show in
                NavigationLink(value: show.id) {
                    ScoreRow(show: show, isFavorite: true) { model.toggleFavorite(show) }
                }.buttonStyle(.plain)
            }
        }
    }
}
