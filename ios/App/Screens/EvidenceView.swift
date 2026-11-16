import SwiftUI
import Charts
import NeochiCore

/// 観点ごとの根拠(起伏・耳・興味)。話の詳細で出す。番組の詳細には出さない(番組は、話の平均だけを見せる)。
struct EvidenceView: View {
    let episode: Episode
    let analysis: EpisodeAnalysis
    /// 開いている観点(観点名)。
    @State private var openAxes: Set<String> = []

    var body: some View { evidence(episode, analysis) }

    private func sectionHead(_ text: String) -> some View { Text(text).ncText(NCText.headline) }

    // MARK: 観点ごとの根拠(最新の解析済みの回だけ)

    private func evidence(_ e: Episode, _ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack(alignment: .firstTextBaseline) {
                sectionHead("観点ごとの根拠")
                Spacer()
                Text(NCString.analyzedEpisode(DetailMath.episodeNumber(e))).ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
            // 起伏と興味は、判定が済んでいなくても行を出し「判定待ち」と書く(評点に何が入っているかを見せる)。
            VStack(spacing: 0) {
                if let v = a.calmStar {
                    axis("起伏の少なさ", star: v, tone: .star(v)) { calmDetail(a) }
                } else {
                    pendingAxis("起伏の少なさ")
                }
                if let v = a.earStar {
                    Divider().overlay(Color.nc(.line))
                    axis("耳のゆるさ", star: v, tone: .star(v)) { earDetail(a) }
                }
                Divider().overlay(Color.nc(.line))
                if let l = a.interest {
                    let total = a.interestScore ?? Explain.interestTotal(a.interestItems)
                    axis("程よい興味", text: interestWord(l), tone: .interestTotal(total)) { interestDetail(a, total: total) }
                } else {
                    pendingAxis("程よい興味")
                }
            }
            .padding(.horizontal, NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
    }

    /// 判定がまだの観点の行。開かない。
    private func pendingAxis(_ title: String) -> some View {
        HStack(spacing: NCSpace.s2) {
            Text(title).ncText(NCText.body)
            Spacer()
            Text(NCString.judgePending).ncText(NCText.footnote, .textSub)
        }
        .frame(minHeight: NCSize.tapMin)
        .accessibilityElement(children: .combine)
    }

    // 起伏の少なさ: 判定の一行 → 1分ごとの起伏の線 → 4項目の行 → 計算式の注記。
    private func calmDetail(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            if !a.calmPerMin.isEmpty {
                Text(DetailMath.calmCurveVerdict(a.moments, minutes: a.calmPerMin.count)).ncText(NCText.body)
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("起伏の強さ(1分ごと、AIの推定)").ncText(NCText.footnote, .textSub)
                    CalmCurveChart(values: a.calmPerMin, moments: a.moments.filter { $0.minute < a.calmPerMin.count })
                }
            } else if !a.calmItems.isEmpty {
                Text(Explain.calmVerdict(a.calmItems)).ncText(NCText.body)
            }
            if !a.calmItems.isEmpty {
                itemRows(a.calmItems, labels: Explain.calmLabels, toned: true)
                Text("項目は 0〜2 点。合計が小さいほど、★が多くなります(5 − 合計×0.75)").ncText(NCText.caption, .textSub)
            }
            if a.calmPerMin.isEmpty {   // 古い解析: 線がないので、目立つ箇所を文字で出す
                ForEach(a.moments, id: \.self) { m in
                    (Text("\(m.minute)分").font(.nc(NCText.numSm)).foregroundStyle(Color.nc(.accentFactor))
                     + Text("  \(m.note)").font(.nc(NCText.footnote)).foregroundStyle(Color.nc(.textSub)))
                }
            }
        }
    }

    // 耳のゆるさ: 話す速さと音量を、同じ横軸で縦に並べる。下に4項目それぞれの理由。
    private func earDetail(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            EarCharts(analysis: a)
            let parts = Explain.earParts(a)
            if !parts.isEmpty {
                VStack(spacing: 0) { ForEach(parts) { partRow($0) } }
            }
        }
    }

    // 程よい興味: 内容の要約 → 5項目の行 → 10段の目盛り(と注記)。
    private func interestDetail(_ a: EpisodeAnalysis, total: Int) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            if let summary = a.contentSummary {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(NCString.summaryHeader).ncText(NCText.caption, .textSub)
                    Text(summary).ncText(NCText.footnote).fixedSize(horizontal: false, vertical: true)
                }
                .padding(NCSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NCRadius.sm, style: .continuous).fill(Color.nc(.bgBase)))
                .accessibilityElement(children: .combine)
            }
            if !a.interestItems.isEmpty {
                itemRows(a.interestItems, labels: Explain.interestLabels)
            }
            InterestScale(total: total)
        }
    }

    /// 採点項目を1行ずつ。点(●●○)と、根拠になった分。
    /// toned: 起伏の項目。0点は緑、1点は琥珀、2点は赤。興味の項目は、1つずつでは良し悪しが決まらないので琥珀のまま。
    private func itemRows(_ items: [ScoredItem], labels: [String: String], toned: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.key) { it in
                let on: NCColor = toned ? EvidenceTone.calmItem(it.score).color : .accentFactor
                HStack(spacing: NCSpace.s2) {
                    Text(labels[it.key] ?? it.key).ncText(NCText.footnote)
                    Spacer()
                    if let m = it.minute, it.score > 0 { Text("\(m)分ごろ").ncText(NCText.caption, .textSub) }
                    Text(Explain.levelWord(it.score)).ncText(NCText.footnote, toned || it.score > 0 ? on : .textSub)
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle().fill(i < it.score ? Color.nc(on) : Color.nc(.line)).frame(width: 8, height: 8)
                        }
                    }
                }.frame(minHeight: 32)
            }
        }
    }

    /// 🎧 の1項目を1行で: 項目名・測った値・満点から最低の間の位置(ゲージ)・★。
    /// 結果のひとこと(「音量が安定しています」など)は読み上げに回し、基準は「解析について」にまとめた。
    private func partRow(_ r: EarPartReport) -> some View {
        let tone = EvidenceTone.unit(r.fill).color
        return HStack(spacing: NCSpace.s2) {
            Text(r.title).ncText(NCText.footnote).frame(width: 92, alignment: .leading)
            Text(r.short).ncText(NCText.numSm).frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.8).lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.nc(.line))
                    Capsule().fill(Color.nc(tone)).frame(width: max(4, g.size.width * CGFloat(r.fill)))
                }
            }
            .frame(width: 56, height: 6)
            Text(r.star.map { String(format: "%.1f", $0) } ?? "―").ncText(NCText.numSm, tone)
                .frame(width: 30, alignment: .trailing)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.title)
        .accessibilityValue("\(r.short)。\(r.verdict)。評点 \(r.star.map { String(format: "%.1f", $0) } ?? "なし")")
    }

    private func interestWord(_ l: InterestLevel) -> String { NCString.interestWord(l) }

    /// 開閉できる観点の行。右に★(または言葉)を出し、押すと根拠が開く。
    private func axis<Content: View>(_ title: String, star: Double? = nil, text: String? = nil, tone: EvidenceTone = .mid,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        let open = openAxes.contains(title)
        return VStack(alignment: .leading, spacing: 0) {
            // 見出しの行だけが開閉する(中の図を押しても閉じない)。
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if open { openAxes.remove(title) } else { openAxes.insert(title) }
                }
            } label: {
                HStack(spacing: NCSpace.s2) {
                    Text(title).ncText(NCText.body)
                    Spacer()
                    if let star {
                        Text("★").ncText(NCText.numSm, tone.color)
                        Text(String(format: "%.1f", star)).ncText(NCText.numMd, tone.color)
                    } else if let text {
                        Text(text).ncText(NCText.body, tone.color)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.nc(.textSub))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: NCSize.tapMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(open ? "開いています" : "閉じています")
            if open {
                content().padding(.bottom, NCSpace.s3)
            }
        }
    }

}

/// 「解析について」(閉じた状態から開く)。解析の深さと、耳のゆるさの基準。
struct AboutAnalysis: View {
    let analysis: EpisodeAnalysis

    var body: some View { about(analysis) }

    private func about(_ a: EpisodeAnalysis) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                Text(aboutText(a))
                Text(NCString.rankCriteriaNote)
                Link(NCString.explainerLinkLabel, destination: NCString.explainerURL)
            }
            .ncText(NCText.footnote, .textSub).frame(maxWidth: .infinity, alignment: .leading).padding(.top, NCSpace.s2)
        } label: {
            Text("解析について").ncText(NCText.footnote, .textSub)
        }.tint(Color.nc(.textSub))
    }

    private func aboutText(_ a: EpisodeAnalysis) -> String {
        let depth: String
        switch a.inputDepth {
        case "audio": depth = "音響の分析だけで判定しています。"
        case "transcript": depth = "冒頭を文字起こしして判定しています。"
        default: depth = "番組の説明文だけで判定しています。"
        }
        let criteria = Explain.earParts(EpisodeAnalysis(episodeID: "", speechRate: 0, speechRateCV: 0, volumeStdDB: 0, suddenPer10Min: 0))
            .map { "\($0.title): \($0.criterion)" }.joined(separator: "\n")
        return "耳のゆるさの基準(★5が満点、★1が最低)\n" + criteria + "\n\n" + "音量の推移と突発音は、冒頭30分を測っています。話す速さと、起伏・興味の判定は、冒頭を文字起こしして行っています。30分以降を聴くのは寝つけなかったときだけなので、内容の評価は冒頭20分までにしています。" + depth
    }

}
