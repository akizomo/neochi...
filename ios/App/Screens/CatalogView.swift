#if DEBUG
import SwiftUI
import NeochiCore

/// 部品とトークンのカタログ(Storybook の代わり)。開発用のビルドだけで、設定のいちばん下から開く。
/// 新しい部品やトークンを足したら、ここにも並べる。画面では、ここにある部品とトークンだけで組む。
struct CatalogView: View {
    var body: some View {
        List {
            Section("トークン") {
                NavigationLink("色") { ColorTokens() }
                NavigationLink("文字") { TypeTokens() }
                NavigationLink("余白・角丸・サイズ") { SpaceTokens() }
            }
            Section("部品") {
                NavigationLink("ボタン") { ButtonCatalog() }
                NavigationLink("評点・格付け") { ScoreCatalog() }
                NavigationLink("カード・一覧の行") { CardCatalog() }
                NavigationLink("入力(評価)") { InputCatalog() }
                NavigationLink("寝落ちまでの表示") { LatencyCatalog() }
                NavigationLink("そのほか") { MiscCatalog() }
            }
        }
        .navigationTitle("部品カタログ")
    }
}

// MARK: - 共通の枠

/// 見出しと、部品を置く面。ライト・ダークは端末の外観で切り替えて確かめる。
private struct Specimen<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Text(title).ncText(NCText.headline)
            if let note { Text(note).ncText(NCText.caption, .textSub) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, NCSpace.s3)
    }
}

private struct CatalogPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NCSpace.s4) { content() }
                .padding(NCSpace.s4)
        }
        .background(Color.nc(.bgBase))
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - トークン

private struct ColorTokens: View {
    var body: some View {
        CatalogPage(title: "色") {
            ForEach(NCColor.allCases, id: \.self) { c in
                HStack(spacing: NCSpace.s3) {
                    RoundedRectangle(cornerRadius: NCRadius.sm).fill(Color.nc(c))
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: NCRadius.sm).strokeBorder(Color.nc(.line), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.rawValue).ncText(NCText.body)
                        Text("NCColor.\(String(describing: c))").ncText(NCText.caption, .textSub)
                    }
                }
            }
        }
    }
}

private struct TypeTokens: View {
    private let styles: [(String, NCTextStyle)] = [
        ("title", NCText.title), ("headline", NCText.headline), ("body", NCText.body), ("footnote", NCText.footnote),
        ("caption", NCText.caption), ("button-l", NCText.buttonL), ("button-m", NCText.buttonM), ("button-s", NCText.buttonS),
        ("num-lg", NCText.numLg), ("num-md", NCText.numMd), ("num-sm", NCText.numSm), ("num-xs", NCText.numXs),
    ]
    var body: some View {
        CatalogPage(title: "文字") {
            ForEach(styles, id: \.0) { name, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.hasPrefix("num") ? "18 4.7" : "寝落ちに向く番組").ncText(s)
                    Text("\(name) · \(Int(s.size))/\(Int(s.lineHeight)) · \(s.weight)").ncText(NCText.caption, .textSub)
                }
            }
        }
    }
}

private struct SpaceTokens: View {
    private let spaces: [(String, Double)] = [("s1", NCSpace.s1), ("s2", NCSpace.s2), ("s3", NCSpace.s3), ("s4", NCSpace.s4),
                                             ("s5", NCSpace.s5), ("s6", NCSpace.s6), ("s8", NCSpace.s8), ("s12", NCSpace.s12)]
    private let radii: [(String, Double)] = [("sm", NCRadius.sm), ("md", NCRadius.md), ("lg", NCRadius.lg)]
    private let sizes: [(String, Double)] = [("tap-min", NCSize.tapMin), ("button-h", NCSize.buttonH), ("button-h-m", NCSize.buttonHM),
                                            ("button-h-s", NCSize.buttonHS), ("row-h", NCSize.rowH)]
    var body: some View {
        CatalogPage(title: "余白・角丸・サイズ") {
            Specimen(title: "余白(NCSpace)") {
                ForEach(spaces, id: \.0) { n, v in
                    HStack { Rectangle().fill(Color.nc(.accentResult)).frame(width: v, height: 12); Text("\(n) · \(Int(v))").ncText(NCText.caption, .textSub) }
                }
            }
            Specimen(title: "角丸(NCRadius)") {
                HStack(spacing: NCSpace.s4) {
                    ForEach(radii, id: \.0) { n, v in
                        VStack { RoundedRectangle(cornerRadius: v).fill(Color.nc(.surface)).frame(width: 64, height: 48)
                            Text("\(n) · \(Int(v))").ncText(NCText.caption, .textSub) }
                    }
                }
            }
            Specimen(title: "サイズ(NCSize)") {
                ForEach(sizes, id: \.0) { n, v in
                    HStack { Rectangle().fill(Color.nc(.line)).frame(width: 24, height: v); Text("\(n) · \(Int(v))").ncText(NCText.caption, .textSub) }
                }
            }
        }
    }
}

// MARK: - 部品

private struct ButtonCatalog: View {
    private let kinds: [(String, NCButtonKind)] = [("主 primary", .primary), ("副 secondary", .secondary), ("文字だけ text", .text)]
    private let sizes: [(String, NCButtonSize)] = [("大 large", .large), ("中 medium", .medium), ("小 small", .small)]

    var body: some View {
        CatalogPage(title: "ボタン") {
            Text("NCButton: 種類 × 大きさ。文字(button-l / m / s)と高さは大きさで決まり、種類では変わらない。")
                .ncText(NCText.footnote, .textSub)
            ForEach(sizes, id: \.0) { sn, s in
                Specimen(title: sn) {
                    ForEach(kinds, id: \.0) { kn, k in
                        NCButton(title: kn, kind: k, size: s, fullWidth: s != .small) {}
                    }
                    NCButton(title: "アイコンつき", icon: "moon", kind: .primary, size: s, fullWidth: s != .small) {}
                    NCButton(title: "押せない", kind: .primary, size: s, fullWidth: s != .small) {}.disabled(true)
                }
            }
            Specimen(title: "ReserveButton", note: "今夜聴く・明日聴く。予約すると「予約済み」(副・枠が濃い)") {
                HStack(spacing: NCSpace.s2) {
                    ReserveButton(night: 0, reserved: false) {}
                    ReserveButton(night: 1, reserved: false) {}
                }
                HStack(spacing: NCSpace.s2) {
                    ReserveButton(night: 0, reserved: true) {}
                    ReserveButton(night: 1, reserved: true) {}
                }
            }
            Specimen(title: "FavoriteButton") {
                HStack { FavoriteButton(isOn: false, title: "見本") {}; FavoriteButton(isOn: true, title: "見本") {} }
            }
        }
    }
}

private struct ScoreCatalog: View {
    var body: some View {
        CatalogPage(title: "評点・格付け") {
            Specimen(title: "StarScore") {
                HStack(spacing: NCSpace.s4) { StarScore(star: 4.7); StarScore(star: 3.2); StarScore(star: nil) }
            }
            Specimen(title: "RankBadge") {
                HStack(spacing: NCSpace.s3) {
                    RankBadge(rank: .zzz); RankBadge(rank: .zz); RankBadge(rank: .z); RankBadge(rank: .zzz, compact: true)
                }
            }
            if let show = SampleData.shows.first {
                Specimen(title: "MetricsRow", note: "カードと一覧では★だけ") { MetricsRow(show: show) }
            }
        }
    }
}

private struct CardCatalog: View {
    var body: some View {
        CatalogPage(title: "カード・一覧の行") {
            if let show = SampleData.shows.first {
                let c = Candidate(show: show, episode: SampleData.episodeMap[show.id]?.first, playCount: 1, reason: .latest)
                Specimen(title: "TonightCard") {
                    TonightCard(candidate: c, primaryTitle: "今夜聴く", primaryIcon: "moon") {}
                }
                Specimen(title: "TonightCard(予約済み)", note: "副ボタンと、その下の一言") {
                    TonightCard(candidate: c, primaryTitle: "取り消す", primaryIcon: "xmark", secondary: true,
                                note: "23:00ごろアプリを開くと、この話をすぐ再生できます") {}
                }
                Specimen(title: "ScoreRow") {
                    ScoreRow(show: show, isFavorite: false) {}
                    ScoreRow(show: show, isFavorite: true) {}
                }
            }
        }
    }
}

private struct InputCatalog: View {
    @State private var interest: Int? = 5
    @State private var calm: Int? = 4
    var body: some View {
        CatalogPage(title: "入力(評価)") {
            Specimen(title: "InterestRatingPicker") { InterestRatingPicker(selection: $interest) }
            Specimen(title: "ChoiceScale") {
                ChoiceScale(question: NCString.calmQuestion, info: NCString.infoCalm, count: 5, selection: $calm,
                            leading: NCString.calmLow, trailing: NCString.calmHigh)
            }
        }
    }
}

private struct LatencyCatalog: View {
    var body: some View {
        CatalogPage(title: "寝落ちまでの表示") {
            Specimen(title: "LatencyGauge", note: "ゾーン: すぐ / 理想 / やや粘り / 長め") {
                ForEach([6, 15, 25, 40], id: \.self) { LatencyGauge(minutes: $0) }
                LatencyGauge(minutes: 25, approximate: true)
            }
            Specimen(title: "RecentNightsChart") {
                RecentNightsChart(nights: [34, 22, 14, 41, 18].enumerated().map { i, m in
                    .init(id: "\(i)", date: Date().addingTimeInterval(Double(i - 4) * 86400), minutes: m, current: i == 4)
                })
            }
            Specimen(title: "DataAccordion") {
                DataAccordion(title: "最近の夜と比べる") { Text("中身").ncText(NCText.body) }
            }
        }
    }
}

private struct MiscCatalog: View {
    var body: some View {
        CatalogPage(title: "そのほか") {
            Specimen(title: "ToastView") { ToastView(text: "今夜聴くに決めました") }
            Specimen(title: "InfoButton") { InfoButton(text: "説明の吹き出し") }
            Specimen(title: "LogoAnimationView") { LogoAnimationView() }
        }
    }
}
#endif
