import SwiftUI
import NeochiCore
import Nuke
import NukeUI

/// 配信元のカバー画像。複製せず URL から読み込む。ないとき・読み込み前は、頭文字の無地。
struct ArtworkView: View {
    let show: Show
    var size: CGFloat = NCSize.artworkS
    var radius: CGFloat = NCRadius.md
    /// 寝落ち格付けのバッジを、右上に重ねる(評点の数字の横には置かない)。
    var showsRank = false

    var body: some View {
        ZStack {
            Color.nc(.bgBase)
            if let url = ArtworkLoader.secure(show.artworkURL) {
                // 表示サイズに縮小して、縮小後の画像をディスクに残す(原寸は 1.5〜10MB のものがある)。
                LazyImage(request: ArtworkLoader.request(url, points: size)) { state in
                    if let image = state.image { image.resizable().scaledToFill() } else { initial }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.nc(.line), lineWidth: NCSize.borderW))
        .overlay(alignment: .topTrailing) {
            if showsRank, show.rank != nil {
                RankBadge(rank: show.rank, compact: size < NCSize.artworkL)
                    .padding(size < NCSize.artworkL ? 3 : NCSpace.s2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var initial: some View {
        Text(String(show.title.prefix(1))).ncText(NCText.headline, .textSub)
    }
}

/// カバー画像の取得の設定(Nuke)。
enum ArtworkLoader {
    /// 起動時に一度。縮小後の画像だけをディスクに保存する(.automatic: 加工済みの画像は残し、原寸は残さない)。
    static func configure() {
        var config = ImagePipeline.Configuration.withDataCache(name: "neochi.artwork", sizeLimit: 150 * 1024 * 1024)
        config.dataCachePolicy = .automatic
        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    /// 暗号化なしの http は iOS が止めるので、https に置き換えて取る(置き換えて取れない配信元は、頭文字の無地のまま)。
    static func secure(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.scheme == "http", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.scheme = "https"
        return c.url
    }

    /// 表示サイズ(pt)の正方形に、中央で切り抜いて縮小する。
    static func request(_ url: URL, points: CGFloat) -> ImageRequest {
        ImageRequest(url: url, processors: [
            ImageProcessors.Resize(size: CGSize(width: points, height: points), unit: .points, contentMode: .aspectFill, crop: true)
        ])
    }
}

/// 押している間だけ、少し薄く・小さくなる。標準のボタンのように、押したことが目に見える。
/// (`.plain` は押しても何も変わらないので、代わりにこれを使う。)
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// 操作の結果を、画面の下に短く出す。iOS に標準のトーストはないので、押した結果をひとこと返すための部品。
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .ncText(NCText.body, .bgBase)
            .padding(.horizontal, NCSpace.s4).padding(.vertical, NCSpace.s3)
            .background(Capsule().fill(Color.nc(.textMain)))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// カードの面を押したとき、面だけが少し沈む(中身は動かさない)。
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
        .buttonStyle(.pressable)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityLabel(isOn ? "\(title)をお気に入りから外す" : "\(title)をお気に入りに追加")
    }
}

/// 寝落ち格付け Z / ZZ / ZZZ。ランクが上がるほど光沢が強い金属(Z は錫、ZZ は青みの銀、ZZZ は虹色の真珠)。
/// 光沢はこのバッジだけの例外。ほかの部品は影を使わない。見本はロゴのキャンバスの「格付けバッジの質感」。
struct RankBadge: View {
    let rank: ZRank?
    /// 小さなカバー画像(一覧の行)に重ねるときの、小さい版。
    var compact = false

    private func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    private var metal: [Color] {
        switch rank {
        case .zzz: return [0x8C7FC9, 0xD9D2FA, 0xFFFFFF, 0xBFE3F4, 0xE7D9FB, 0x9A8BD8].map(hex)
        case .zz: return [0x6E86A8, 0xB9CCE6, 0xF1F6FD, 0xA8BEDC, 0x5F7899].map(hex)
        default: return [0x5E6673, 0x9AA2AE, 0xC3C9D2, 0x8A929F, 0x5A616D].map(hex)
        }
    }

    private var ink: Color {
        switch rank {
        case .zzz: return hex(0x1C1638)
        case .zz: return hex(0x14202F)
        default: return hex(0x1E232C)
        }
    }

    var body: some View {
        if let rank {
            Text(rank.rawValue).font(.system(size: compact ? 10 : 13, weight: .bold, design: .monospaced)).foregroundStyle(ink)
                .padding(.horizontal, compact ? NCSpace.s1 + 1 : NCSpace.s3).frame(minHeight: compact ? 16 : NCSize.badgeH)
                .background(Capsule().fill(LinearGradient(colors: metal, startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                .accessibilityLabel("寝落ち格付け \(rank.rawValue)")
        }
    }
}

/// 評点は ★ と数字(琥珀)。格付けのバッジは、カバー画像の右上に置く。
struct StarScore: View {
    let star: Double?
    var style: NCTextStyle = NCText.numMd

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
            Text("★").font(.system(size: style.size * 0.6)).foregroundStyle(Color.nc(.accentFactor))
            Text(star.map { String(format: "%.1f", $0) } ?? "―").ncText(style, .accentFactor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(star.map { "評点 \(String(format: "%.1f", $0))" } ?? "評点 なし")
    }
}

/// 左に評点(★と数字)、右にウォッチの実測の平均。
struct MetricsRow: View {
    let show: Show

    var body: some View {
        HStack(spacing: NCSpace.s3) {
            StarScore(star: show.star)
            Rectangle().fill(Color.nc(.line)).frame(width: NCSize.borderW, height: NCSize.dividerH)
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
            ArtworkView(show: show, showsRank: true)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text(show.title).ncText(NCText.headline).lineLimit(1).truncationMode(.tail)
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

    private var surface: some View {
        RoundedRectangle(cornerRadius: NCRadius.lg, style: .continuous).fill(Color.nc(.surface))
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)   // 面を、背景から浮かせる
            .contentShape(RoundedRectangle(cornerRadius: NCRadius.lg, style: .continuous))
    }

    var body: some View {
        // カードぜんたいが、詳細への入口。下のレイヤーがカードの面(押すと少し沈む)で、
        // 上のレイヤーの文字や画像は、タップを下へ通す。主ボタンだけが別の操作。
        ZStack {
            // 話を提案しているカードは、話の詳細へ。話が決まっていない(明日以降の「続き」)ときは、番組の詳細へ。
            Group {
                if let ep = candidate.episode {
                    NavigationLink(value: EpisodeRoute(id: ep.id)) { surface }
                } else {
                    NavigationLink(value: candidate.show.id) { surface }
                }
            }
            .buttonStyle(CardPressStyle())
            VStack(spacing: NCSpace.s2) {
                Group {
                    // どのカードも同じ高さにする。題名は2行ぶん、理由と回の行は1行ぶんを、いつも確保する。
                    ReasonText(reason: candidate.reason).lineLimit(1).frame(minHeight: NCSpace.s5)
                    ArtworkView(show: candidate.show, size: NCSize.artworkXl, radius: NCRadius.lg, showsRank: true)
                    Text(candidate.show.title).ncText(NCText.title)
                        .lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
                    MarqueeText(text: episodeLine, style: NCText.footnote, color: .textSub, centered: true)
                    MetricsRow(show: candidate.show).padding(.top, NCSpace.s2)
                }
                .allowsHitTesting(false)
                Button(action: onPrimary) {
                    Label(primaryTitle, systemImage: primaryIcon)
                        .ncText(NCText.headline, .bgBase)
                        .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                        .background(Capsule().fill(Color.nc(.textMain)))
                }
                .buttonStyle(.pressable)
                .padding(.top, NCSpace.s3)
            }
            .padding(NCSpace.s4)
        }
        .frame(maxWidth: .infinity)
    }

    private var episodeLine: String {
        let title = candidate.episode?.title ?? "続きの話"
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
        .buttonStyle(.pressable)
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

/// 差のピル(矢印のアイコン+値+比べた相手)。番組にとって良い向きは positive、良くない向きは negative、差がなければ無彩色。
/// 向きは矢印でも示し、色だけに頼らない。人の睡眠の良し悪しの評価には使わない(番組の数字の変化だけ)。
struct DeltaPill: View {
    /// 差(正 = 増えた)。
    let delta: Double
    /// どちら向きが番組にとって良いか。
    let polarity: DeltaPolarity
    /// 値の書き方。例 { "\(Int(abs($0).rounded()))分" }
    let format: (Double) -> String
    /// 比べた相手。例「前の4件」
    let caption: String
    /// 読み上げの言葉(増えた/減った)。例 ("長い", "短い")
    var spoken: (up: String, down: String) = ("多い", "少ない")

    private var text: String { format(abs(delta)) }
    private var isFlat: Bool { format(0) == text }
    private var tone: DeltaTone { DetailMath.tone(delta, polarity, flat: isFlat) }
    private var fg: NCColor { tone == .positive ? .positive : tone == .negative ? .negative : .textMain }
    private var bg: NCColor { tone == .positive ? .positiveTint : tone == .negative ? .negativeTint : .surfacePressed }

    var body: some View {
        HStack(spacing: NCSpace.s1) {
            HStack(spacing: 3) {
                Image(systemName: isFlat ? "equal" : delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: NCSize.iconSm, weight: .semibold))
                    .frame(width: NCSize.iconSm, height: NCSize.iconSm)
                Text(isFlat ? "\(text)" : text).font(.nc(NCText.numSm))
            }
            Text(caption).font(.nc(NCText.caption))
        }
        .foregroundStyle(Color.nc(fg))
        .padding(.horizontal, NCSpace.s2).padding(.vertical, 3)
        .background(Capsule().fill(Color.nc(bg)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFlat ? "\(caption)と同じ" : "\(caption)より \(text) \(delta > 0 ? spoken.up : spoken.down)")
    }
}

/// 1行に収まらない題名を、省略せず、ゆっくり横に流す(よくある電光掲示の動き)。
/// - 収まるときは、ふつうの文字のまま(中央寄せも指定できる)。
/// - 収まらないときは、2秒止まって → 左へ流れ → 頭から続けて回る。両端は薄く消える。
/// - 「視差効果を減らす」のときは流さず、末尾を省略する。画面が非アクティブの間は止める。
struct MarqueeText: View {
    let text: String
    var style: NCTextStyle = NCText.body
    var color: NCColor = .textMain
    var centered = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var textW: CGFloat = 0
    @State private var boxW: CGFloat = 0

    private let gap: CGFloat = 40, speed: Double = 28, pause: Double = 2
    private var overflow: Bool { textW > boxW + 0.5 && boxW > 0 }
    private var scrolling: Bool { overflow && !reduceMotion }

    var body: some View {
        Text(text).ncText(style, color).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .opacity(scrolling ? 0 : 1)
            .background(GeometryReader { g in Color.clear.onAppear { boxW = g.size.width }.onChange(of: g.size.width) { _, w in boxW = w } })
            .background(
                Text(text).ncText(style, color).fixedSize().hidden()
                    .background(GeometryReader { g in Color.clear.onAppear { textW = g.size.width }.onChange(of: g.size.width) { _, w in textW = w } })
            )
            .overlay {
                if scrolling {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { tl in
                        let span = Double(textW + gap), run = span / speed, cycle = pause + run
                        let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                        let x = -CGFloat(max(0, t - pause) * speed)
                        HStack(spacing: gap) {
                            Text(text).ncText(style, color).fixedSize()
                            Text(text).ncText(style, color).fixedSize()
                        }
                        .offset(x: x)
                        .frame(width: boxW, alignment: .leading)
                        .clipped()
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                                     .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// 話の詳細への行き先。番組の詳細は、番組のID(文字列)で開く。
struct EpisodeRoute: Hashable { let id: String }

/// アプリの行き先(番組の詳細・話の詳細・記録の詳細)。どのタブの画面からも、同じ行き先に進めるよう、各タブの NavigationStack の中に付ける。
private struct AppDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: String.self) { DetailView(showID: $0) }
            .navigationDestination(for: EpisodeRoute.self) { EpisodeDetailView(episodeID: $0.id) }
            .navigationDestination(for: LogRoute.self) { RecordDetailView(logID: $0.id) }
    }
}

extension View {
    func appDestinations() -> some View { modifier(AppDestinations()) }
}
