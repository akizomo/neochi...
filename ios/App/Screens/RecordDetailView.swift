import SwiftUI
import NeochiCore

/// 記録の詳細。結果(分数)を先に、番組、睡眠データ(実測のときだけ)、つけた評価、メモ。
/// 睡眠の点数や質の評価は出さない。入眠の時刻だけ。
struct RecordDetailView: View {
    @Environment(AppModel.self) private var model
    let logID: String
    @State private var note = ""
    @State private var noteOpen = false
    @State private var loaded = false
    @State private var editingRatings = false
    @State private var interest: Int?
    @State private var calm: Int?

    private var log: SleepLog? { model.logs.first { $0.id == logID } }
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日 EEEE"; return f
    }()
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "H:mm"; return f
    }()

    var body: some View {
        ScrollView {
            if let log, let show = model.shows.first(where: { $0.id == log.showID }) {
                VStack(alignment: .leading, spacing: NCSpace.s4) {
                    Text(Self.dayFormat.string(from: log.startedAt) + (log.source == .selfReport ? "(自己申告)" : ""))
                        .ncText(NCText.footnote, .textSub)
                    result(log)
                        .padding(NCSpace.s4).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))   // 朝の振り返りと同じカード
                    showRow(show, log)
                    ratings(log)
                    memo(log)
                }
                .padding(NCSpace.s4)
            }
        }
        .background(Color.nc(.bgBase))
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if !loaded { note = log?.note ?? ""; noteOpen = !note.isEmpty; loaded = true } }
        .onDisappear { model.updateNote(logID: logID, note: note) }
    }

    private func result(_ log: SleepLog) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            if let m = log.latencyMinutes {
                HStack(alignment: .firstTextBaseline, spacing: NCSpace.s2) {
                    Text("\(m)").ncText(NCText.numHero, .accentResult)
                    Text("分").ncText(NCText.title, .accentResult)
                }
                Text(NCString.comment(minutes: m)).ncText(NCText.body)
                if log.source == .watch {
                    LatencyGauge(minutes: m).padding(.top, NCSpace.s2)
                    let recent = model.recentNights(upTo: log.startedAt, currentLogID: log.id)
                    DataAccordion(title: "最近の夜と睡眠データ") {
                        VStack(alignment: .leading, spacing: NCSpace.s4) {
                            if recent.count >= 2 { RecentNightsChart(nights: recent) }
                            sleepCard(log, minutes: m)
                        }
                    }
                }
            } else if let r = log.selfReport {
                Text(r.label).ncText(NCText.title, .accentResult)
                Text(r.hint).ncText(NCText.body, .textSub)
            } else {
                Text("―").ncText(NCText.numHero, .textSub)
                Text("寝落ちの記録を確認中です").ncText(NCText.title)
            }
        }
    }

    private func showRow(_ show: Show, _ log: SleepLog) -> some View {
        let ep = model.episodes[show.id]?.first { $0.id == log.episodeID }?.title
        return NavigationLink(value: show.id) {
            HStack(spacing: NCSpace.s3) {
                ArtworkView(show: show)
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    MarqueeText(text: show.title, style: NCText.headline)
                    if let ep, !ep.isEmpty { MarqueeText(text: ep, style: NCText.footnote, color: .textSub) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").ncText(NCText.footnote, .textSub)
            }
        }.buttonStyle(.pressable)
    }

    /// 再生開始 → 入眠(推定)。再生終了は、回の長さ(最大60分)。
    private func sleepCard(_ log: SleepLog, minutes m: Int) -> some View {
        let durationMin = (model.episodes[log.showID]?.first { $0.id == log.episodeID }?.durationSec).map { min(60, $0 / 60) }
        let endMin = max(durationMin ?? max(m, 1), m)
        return VStack(alignment: .leading, spacing: NCSpace.s3) {
            HStack {
                Text("睡眠データ").ncText(NCText.headline)
                Spacer()
                Text("ヘルスケアの実測").ncText(NCText.caption, .textSub)
            }
            GeometryReader { g in
                let x = g.size.width * CGFloat(m) / CGFloat(max(endMin, 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.nc(.line))
                    Capsule().fill(Color.nc(.accentResult)).frame(width: max(8, x))
                }
            }.frame(height: 10)
            HStack {
                fact("再生開始", log.startedAt, .textMain)
                Spacer()
                if let o = log.sleepOnsetAt { fact("入眠(推定)", o, .accentResult) }
                Spacer()
                fact("再生終了", log.startedAt.addingTimeInterval(Double(endMin) * 60), .textMain)
            }
        }
    }

    private func fact(_ title: String, _ date: Date, _ color: NCColor) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s1) {
            Text(title).ncText(NCText.caption, .textSub)
            Text(Self.timeFormat.string(from: date)).ncText(NCText.numSm, color)
        }
    }

    /// つけた評価。あとから変えられる(「変更」で入力に切り替え、「完了」で保存する)。
    private func ratings(_ log: SleepLog) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            HStack {
                Text("つけた評価").ncText(NCText.headline)
                Spacer()
                Button {
                    if editingRatings { model.updateRatings(logID: log.id, interest: interest, calm: calm) }
                    else { interest = log.interestRating; calm = log.calmVote }
                    withAnimation { editingRatings.toggle() }
                } label: {
                    Text(editingRatings ? "完了" : (log.interestRating == nil && log.calmVote == nil ? "つける" : "変更"))
                        .ncText(NCText.footnote, .textSub).frame(minHeight: NCSize.tapMin)
                }
                .buttonStyle(.pressable)
            }
            if editingRatings {
                InterestRatingPicker(selection: $interest)
                ChoiceScale(question: NCString.calmQuestion, info: NCString.infoCalm, count: 5, selection: $calm,
                            leading: NCString.calmLow, trailing: NCString.calmHigh)
            } else {
                if let v = log.interestRating {
                    let z = NCString.interestZone(v)
                    VStack(alignment: .leading, spacing: NCSpace.s2) {
                        HStack {
                            Text("引き込み力").ncText(NCText.footnote, .textSub)
                            Spacer()
                            Text("\(v) / 10 ・ \(NCString.interestZoneName(z))").ncText(NCText.footnote)
                        }
                        HStack(spacing: 3) {
                            ForEach(1...10, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i == v ? Color.nc(.accentFactor) : Color.nc(.line)).frame(height: 8)
                            }
                        }
                        Text(NCString.interestZoneNote(z)).ncText(NCText.caption, .textSub)
                    }
                }
                if let c = log.calmVote {
                    HStack {
                        Text("起伏").ncText(NCText.footnote, .textSub)
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(1...5, id: \.self) { n in
                                Text("★").ncText(NCText.numMd, n <= c ? .accentFactor : .borderControl)
                            }
                        }
                    }
                }
                if log.interestRating == nil && log.calmVote == nil {
                    Text("まだ評価していません").ncText(NCText.footnote, .textSub)
                }
            }
        }
        .padding(NCSpace.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }

    private func memo(_ log: SleepLog) -> some View {
        Group {
            if noteOpen {
                VStack(alignment: .leading, spacing: NCSpace.s2) {
                    Text("メモ").ncText(NCText.headline)
                    TextField("", text: $note, axis: .vertical).lineLimit(1...6).ncText(NCText.body)
                }
                .padding(NCSpace.s4).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
            } else {
                Button { noteOpen = true } label: {
                    Label("メモを追加", systemImage: "plus").ncText(NCText.body)
                        .frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
                        .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
                }
            }
        }
    }
}
