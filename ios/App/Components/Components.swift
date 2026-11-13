import SwiftUI
import NeochiCore

/// 配信元のカバー画像。複製せず URL から読み込む。ないとき・読み込み前は、頭文字の無地。
struct ArtworkView: View {
    let show: Show
    var size: CGFloat = NCSize.artworkS
    var radius: CGFloat = NCRadius.md

    var body: some View {
        ZStack {
            Color.nc(.bgBase)
            if let url = show.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { initial }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.nc(.line), lineWidth: NCSize.borderW))
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(String(show.title.prefix(1))).ncText(NCText.headline, .textSub)
    }
}

/// 番組をお気に入りに入れる。★(評価)と取り違えないよう、ブックマークのアイコン。
struct FavoriteButton: View {
    let isOn: Bool
    let title: String
    /// ツールバー用。システムが枠で包むので、独自の円は付けず、アイコンだけにする(はみ出し防止)。
    var inToolbar = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if inToolbar {
                Image(systemName: isOn ? "bookmark.fill" : "bookmark")
                    .font(.system(size: NCSize.iconMd, weight: .semibold))
                    .foregroundStyle(Color.nc(.textMain))
            } else {
                Image(systemName: isOn ? "bookmark.fill" : "bookmark")
                    .font(.system(size: NCSize.iconMd, weight: .semibold))
                    .frame(width: NCSize.stockD, height: NCSize.stockD)
                    .foregroundStyle(Color.nc(isOn ? .bgBase : .textMain))
                    .background(Circle().fill(isOn ? Color.nc(.textMain) : Color.clear))
                    .overlay(Circle().strokeBorder(Color.nc(.borderControl), lineWidth: isOn ? 0 : NCSize.borderW))
            }
        }
        .accessibilityLabel(isOn ? "\(title)をお気に入りから外す" : "\(title)をお気に入りに追加")
    }
}

/// 掲載ランク Z / ZZ / ZZZ。実測がない番組は「調査中」。
struct RankBadge: View {
    let rank: ZRank?

    var body: some View {
        if let rank {
            Text(rank.rawValue).ncText(NCText.caption, .accentResult)
                .padding(.horizontal, NCSpace.s3).frame(minHeight: NCSize.badgeH)
                .background(Capsule().fill(Color.nc(.resultTint)))
        } else {
            Text(NCString.researching).ncText(NCText.caption, .textSub)
                .padding(.horizontal, NCSpace.s3).frame(minHeight: NCSize.badgeH)
                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: NCSize.borderW))
        }
    }
}

/// 要因(★・琥珀)を左、結果(Z と分数・青灰)を右に並べる。合算しない。
struct MetricsRow: View {
    let show: Show

    var body: some View {
        HStack(spacing: NCSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                Text("★").ncText(NCText.numSm, .accentFactor)
                Text(show.star.map { String(format: "%.1f", $0) } ?? "―").ncText(NCText.numMd, .accentFactor)
            }
            Rectangle().fill(Color.nc(.line)).frame(width: NCSize.borderW, height: NCSize.dividerH)
            HStack(spacing: NCSpace.s2) {
                RankBadge(rank: show.rank)
                if let m = show.avgMinutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text("\(m)").ncText(NCText.numMd, .accentResult)
                        Text("分").ncText(NCText.footnote, .accentResult)
                    }
                } else {
                    Text("―").ncText(NCText.numMd, .textSub)
                }
            }
        }
    }
}

/// 候補の理由。数字は等幅で `accent-result` に強調する。
struct ReasonText: View {
    let reason: Reason

    var body: some View {
        reason.segments.reduce(Text("")) { acc, seg in
            acc + (seg.emphasized
                   ? Text(seg.text).font(.nc(NCText.numSm)).foregroundStyle(Color.nc(.accentResult))
                   : Text(seg.text).font(.nc(NCText.footnote)).foregroundStyle(Color.nc(.textSub)))
        }
    }
}

/// 一覧の1行。カバー、番組名、AIの一行、★と実績、右端にお気に入り。
struct ScoreRow: View {
    let show: Show
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: NCSpace.s3) {
            ArtworkView(show: show)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text(show.title).ncText(NCText.headline).lineLimit(1)
                if let line = show.oneLiner {
                    Text(line).ncText(NCText.footnote, .textSub).lineLimit(2)
                }
                MetricsRow(show: show).padding(.top, NCSpace.s2)
            }
            Spacer(minLength: 0)
            FavoriteButton(isOn: isFavorite, title: show.title, action: onToggleFavorite)
        }
        .padding(.leading, NCSpace.s4).padding(.trailing, NCSpace.s3).padding(.vertical, NCSpace.s3)
        .frame(minHeight: NCSize.rowH)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        .contentShape(Rectangle())
    }
}

/// 今夜の候補を1枚ずつ大きく見せるカード。理由を添え、そのまま再生(または予約)できる。
struct TonightCard: View {
    let candidate: Candidate
    let primaryTitle: String
    let primaryIcon: String
    let onPrimary: () -> Void

    var body: some View {
        VStack(spacing: NCSpace.s2) {
            ReasonText(reason: candidate.reason).frame(minHeight: NCSpace.s5)
            ArtworkView(show: candidate.show, size: NCSize.artworkXl, radius: NCRadius.lg)
            NavigationLink(value: candidate.show.id) {
                Text(candidate.show.title).ncText(NCText.title).multilineTextAlignment(.center)
            }.buttonStyle(.plain)
            Text(episodeLine).ncText(NCText.footnote, .textSub)
            MetricsRow(show: candidate.show).padding(.top, NCSpace.s2)
            Button(action: onPrimary) {
                Label(primaryTitle, systemImage: primaryIcon)
                    .ncText(NCText.headline, .bgBase)
                    .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            .padding(.top, NCSpace.s3)
        }
        .padding(NCSpace.s4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: NCRadius.lg, style: .continuous).fill(Color.nc(.surface)))
    }

    private var episodeLine: String {
        let title = candidate.episode?.title ?? "続きの回"
        return candidate.playCount >= 2 ? "\(title) ・ \(candidate.playCount)回目" : title
    }
}


/// 質問の選択肢を、同じ形で出す部品。数字のセグメントと、その下の言葉(左端・中央・右端)。
/// 3択でも5段階でも、同じ見た目・同じ置き方。何も選ばない(未回答)こともできる。
struct InfoButton: View {
    let text: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "info.circle").font(.system(size: NCSize.iconMd))
                .foregroundStyle(Color.nc(.textSub)).frame(minWidth: NCSize.tapMin, minHeight: NCSize.tapMin)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("説明")
        .popover(isPresented: $open) {
            Text(text).ncText(NCText.body)
                .padding(NCSpace.s4)
                .frame(width: NCSize.popoverW, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct ChoiceScale: View {
    let question: String
    var info: String? = nil
    let count: Int
    @Binding var selection: Int?
    let leading: String
    var middle: String? = nil
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack {
                Text(question).ncText(NCText.headline)
                Spacer()
                if let info { InfoButton(text: info) }
            }
            Picker(question, selection: $selection) {
                ForEach(1...count, id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack {
                Text(leading)
                Spacer()
                if let middle { Text(middle); Spacer() }
                Text(trailing)
            }
            .ncText(NCText.footnote, .textSub)
        }
    }
}
