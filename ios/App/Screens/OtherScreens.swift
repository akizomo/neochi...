import SwiftUI
import NeochiCore

/// 見つける: 発見の場。AIの★が高い順に、ジャンルで絞れる。
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var genre: String?

    private var genres: [String] { Array(Set(model.shows.map(\.genre))).sorted() }
    private var list: [Show] {
        model.shows.filter { genre == nil || $0.genre == genre }.sorted { ($0.star ?? 0) > ($1.star ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s3) {
                    Text("AIのおすすめ順").ncText(NCText.headline).padding(.top, NCSpace.s2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NCSpace.s2) {
                            chip("すべて", selected: genre == nil) { genre = nil }
                            ForEach(genres, id: \.self) { g in chip(g, selected: genre == g) { genre = g } }
                        }
                    }
                    ForEach(list) { show in
                        NavigationLink(value: show.id) {
                            ScoreRow(show: show, isFavorite: model.favorites.contains(show.id)) { model.toggleFavorite(show) }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NCSpace.s5).padding(.bottom, NCSpace.s8)
            }
            .background(Color.nc(.bgBase))
            .navigationDestination(for: String.self) { DetailView(showID: $0) }
            .navigationTitle("見つける")
            .toolbarTitleDisplayMode(.inlineLarge)
            .contentMargins(.top, NCSpace.s5, for: .scrollContent)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ncText(NCText.body, selected ? .bgBase : .textMain)
                .padding(.horizontal, NCSpace.s4).frame(minHeight: NCSize.tapMin)
                .background(Capsule().fill(selected ? Color.nc(.textMain) : Color.clear))
                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: selected ? 0 : NCSize.borderW))
        }
    }
}

/// 記録: 日付ごとの結果(新しい順)。
struct LogView: View {
    @Environment(AppModel.self) private var model

    @State private var editingBedtime = false
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
        .buttonStyle(.plain).disabled(auto)
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
            .sheet(isPresented: $editingBedtime) { BedtimeSetupView(editing: true, initial: model.bedtimeMinute) }
        }
    }

    private func row(_ log: SleepLog) -> some View {
        let title = model.shows.first { $0.id == log.showID }?.title ?? ""
        return HStack(alignment: .center, spacing: NCSpace.s3) {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text(Self.dateFormat.string(from: log.startedAt)).ncText(NCText.footnote, .textSub)
                Text(title).ncText(NCText.headline).lineLimit(1)
                if let note = log.note { Text(note).ncText(NCText.footnote, .textSub).lineLimit(2) }
            }
            Spacer(minLength: NCSpace.s2)
            VStack(alignment: .trailing, spacing: NCSpace.s1) {
                if let m = log.latencyMinutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text("\(m)").ncText(NCText.numMd, .accentResult)
                        Text("分").ncText(NCText.footnote, .accentResult)
                    }
                } else {
                    Text("―").ncText(NCText.numMd, .textSub)
                }
                if let c = log.calmVote {
                    HStack(spacing: NCSpace.s1) {
                        Text("★").ncText(NCText.numSm, .accentFactor)
                        Text("\(c)").ncText(NCText.numSm, .accentFactor)
                    }
                }
            }
        }
        .padding(NCSpace.s4)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }
}
