import SwiftUI
import NeochiCore

/// 見つける: 上から、総合のベスト1番組、寝落ち用の上位、寝落ち用ではないのに眠れる番組、系統で絞れる一覧。
/// 順位は数字だけで出す(「位」とは書かない。`docs/VOICE.md`)。
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var genre: String?

    private var genres: [String] { Discover.genres(in: model.shows) }
    private var list: [Show] {
        Discover.ranked(model.shows.filter { genre == nil || $0.genre == genre })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 系統のチップは、一覧まで来たら画面の上に固定する(絞り込みを、どこからでも変えられる)。
                LazyVStack(alignment: .leading, spacing: NCSpace.s6, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: NCSpace.s6) {
                        if let best = Discover.best(model.shows) { BestCard(show: best) }
                        shelf("寝落ち用の、上位", note: "寝落ち用・朗読・環境音の中から", Discover.sleepMade(model.shows))
                        shelf("寝落ち用ではないのに、寝落ちできる番組", note: "コメディ・雑談・教養の中から", Discover.notSleepMade(model.shows))
                        Text("系統で探す").ncText(NCText.headline)
                    }
                    .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s5)   // 固定するチップの位置に響かないよう、余白は中身に付ける
                    Section {
                        VStack(alignment: .leading, spacing: NCSpace.s3) {
                            ForEach(list) { show in
                                NavigationLink(value: show.id) {
                                    ScoreRow(show: show, isFavorite: model.favorites.contains(show.id)) { model.toggleFavorite(show) }
                                }.buttonStyle(.pressable)
                            }
                        }
                        .padding(.horizontal, NCSpace.s5).padding(.bottom, NCSpace.s8)
                    } header: { genreChips }
                }
            }
            .background(Color.nc(.bgBase))
            .modifier(SoftTopEdge())
            .appDestinations()
            .navigationTitle("見つける")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    /// 横にスクロールする棚。順位は数字だけ。
    @ViewBuilder private func shelf(_ title: String, note: String, _ shows: [Show]) -> some View {
        if !shows.isEmpty {
            VStack(alignment: .leading, spacing: NCSpace.s3) {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(title).ncText(NCText.headline)
                    Text(note).ncText(NCText.footnote, .textSub)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: NCSpace.s3) {
                        ForEach(Array(shows.enumerated()), id: \.element.id) { i, show in
                            NavigationLink(value: show.id) { ShelfCard(rank: i + 1, show: show) }
                                .buttonStyle(.pressable)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// 系統のチップ。固定しても帯は敷かない(iOS 26 では、チップ自体がガラスで、上端は標準のぼかし)。
    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NCSpace.s2) {
                chip("すべて", selected: genre == nil) { genre = nil }
                ForEach(genres, id: \.self) { g in chip(g, selected: genre == g) { genre = g } }
            }
            .padding(.horizontal, NCSpace.s5)
        }
        .padding(.vertical, NCSpace.s2)
        .frame(maxWidth: .infinity)
        .scrollClipDisabled()
    }

    @ViewBuilder private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let label = Text(title).ncText(NCText.body, selected ? .bgBase : .textMain)
            .padding(.horizontal, NCSpace.s4).frame(minHeight: NCSize.tapMin)
        if #available(iOS 26.0, *) {
            Button(action: action) { label }
                .glassEffect(selected ? .regular.tint(Color.nc(.textMain)).interactive() : .regular.interactive(), in: Capsule())
        } else {
            Button(action: action) {
                label
                    .background(Capsule().fill(selected ? Color.nc(.textMain) : Color.nc(.bgBase)))
                    .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: selected ? 0 : NCSize.borderW))
            }
        }
    }
}

/// 総合でいちばん評点の高い番組を、大きく。その場で今夜聴くを予約できる。
private struct BestCard: View {
    @Environment(AppModel.self) private var model
    let show: Show

    var body: some View {
        let reserved = model.isReservedTonight(show)
        ZStack {
            NavigationLink(value: show.id) {
                RoundedRectangle(cornerRadius: NCRadius.lg, style: .continuous).fill(Color.nc(.surface))
                    .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
                    .contentShape(RoundedRectangle(cornerRadius: NCRadius.lg, style: .continuous))
            }
            .buttonStyle(CardPressStyle())
            VStack(spacing: NCSpace.s2) {
                Group {
                    Text("いま、総合でいちばん").ncText(NCText.footnote, .textSub)
                    ArtworkView(show: show, size: NCSize.artworkXl, radius: NCRadius.lg, showsRank: true)
                    Text(show.title).ncText(NCText.title).lineLimit(2).multilineTextAlignment(.center)
                    if let r = show.rank { Text(NCString.rankMeaning(r)).ncText(NCText.footnote, .textSub) }
                    MetricsRow(show: show).padding(.top, NCSpace.s2)
                }
                .allowsHitTesting(false)
                Button { model.toggleTonight(show) } label: {
                    Label(reserved ? "今夜予約済み" : "今夜聴く", systemImage: reserved ? "checkmark" : "moon")
                        .ncText(NCText.headline, reserved ? .textMain : .bgBase)
                        .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                        .background(Capsule().fill(reserved ? Color.clear : Color.nc(.textMain)))
                        .overlay(Capsule().strokeBorder(Color.nc(.textMain), lineWidth: reserved ? 1.5 : 0))
                }
                .buttonStyle(.pressable)
                .padding(.top, NCSpace.s3)
            }
            .padding(NCSpace.s4)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 棚の1枚。左上に順位の数字、カバー、番組名、評点。
private struct ShelfCard: View {
    let rank: Int
    let show: Show

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Text("\(rank)").ncText(NCText.numMd, .textSub)
            ArtworkView(show: show, size: NCSize.artworkL, radius: NCRadius.md, showsRank: true)
            Text(show.title).ncText(NCText.footnote).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            StarScore(star: show.star, style: NCText.headline)
        }
        .frame(width: NCSize.artworkL, alignment: .leading)
    }
}

/// 記録: 日付ごとの結果(新しい順)。
struct LogView: View {
    @Environment(AppModel.self) private var model

    @State private var editingBedtime = false
    @State private var showingAccount = false
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.setLocalizedDateFormatFromTemplate("M/d E"); return f
    }()

    /// ふだんの就寝時刻。履歴が足りないうちは手で決められ、十分になったら自動(ヘルスケアの記録)になる。
    private var bedtimeRow: some View {
        let auto = model.bedtimeIsAuto
        let text = model.bedtimeMinute.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "未設定"
        return Button { editingBedtime = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("ふだんの就寝時刻").ncText(NCText.footnote, .textSub)
                    Text(text).ncText(NCText.numMd)
                }
                Spacer()
                if auto { Text("ヘルスケアの記録から").ncText(NCText.footnote, .textSub) }
                else { HStack(spacing: NCSpace.s1) { Text("変える"); Image(systemName: "chevron.right") }.ncText(NCText.footnote, .textSub) }
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.pressable).disabled(auto)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s3) {
                    bedtimeRow
                    if model.logs.isEmpty {
                        Text("まだ記録がありません。").ncText(NCText.footnote, .textSub)
                    } else {
                        ForEach(model.logs.sorted { $0.startedAt > $1.startedAt }) { log in row(log) }
                    }
                }
                .padding(.horizontal, NCSpace.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.nc(.bgBase))
            .navigationTitle("記録")
            .toolbarTitleDisplayMode(.inlineLarge)
            .contentMargins(.top, NCSpace.s5, for: .scrollContent)
            .appDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAccount = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("アカウント")
                }
            }
            .sheet(isPresented: $showingAccount) { AccountView() }
            .sheet(isPresented: $editingBedtime) { BedtimeSetupView(editing: true, initial: model.bedtimeMinute) }
        }
    }

    private func row(_ log: SleepLog) -> some View {
        let title = model.shows.first { $0.id == log.showID }?.title ?? ""
        let ep = model.episodes[log.showID]?.first { $0.id == log.episodeID }?.title
        return NavigationLink(value: LogRoute(id: log.id)) {
            HStack(alignment: .center, spacing: NCSpace.s3) {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(Self.dateFormat.string(from: log.startedAt)).ncText(NCText.footnote, .textSub)
                    Text(title).ncText(NCText.headline).lineLimit(1).truncationMode(.tail)
                    if let ep, !ep.isEmpty { Text(ep).ncText(NCText.footnote, .textSub).lineLimit(1).truncationMode(.tail) }
                }
                Spacer(minLength: NCSpace.s2)
                if let m = log.latencyMinutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text("\(m)").ncText(NCText.numMd, .accentResult)
                        Text("分").ncText(NCText.footnote, .accentResult)
                    }
                } else {
                    Text("―").ncText(NCText.numMd, .textSub)
                }
                Image(systemName: "chevron.right").ncText(NCText.footnote, .textSub)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.pressable)
    }
}

struct LogRoute: Hashable { let id: String }

/// iOS 26: スクロールの上端を、標準のぼかし(固定したチップの下で、一覧がやわらかく消える)にする。
private struct SoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectStyle(.soft, for: .top) } else { content }
    }
}
