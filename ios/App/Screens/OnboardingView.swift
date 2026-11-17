import SwiftUI
import NeochiCore

/// 初回のオンボーディング。魅力を伝える → しくみを理解してもらう → 必要な設定をする、の順。
/// 1枚のシートの中で進み、最後の許可の画面を除いて、前に戻れる。
/// - 番組の画面は、ジャンルを選んだときだけ。
/// - ヘルスケアの画面は、まだ許可を聞いていないときだけ。許可の前の説明なので、ボタンは「次へ」の1つだけ
///   (押すとシステムの許可画面が出る。断るのは、そちらでできる。HIG: Privacy › Pre-alert screens)。
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Int, CaseIterable { case appeal, understand, genres, shows, health }
    @State private var step: Step = .appeal
    @State private var selected: Set<String> = []
    @State private var requesting = false

    /// この人に出すステップ(選んだジャンルと、許可の状態で変わる)。
    private var steps: [Step] {
        Step.allCases.filter {
            switch $0 {
            case .shows: return !selected.isEmpty
            case .health: return model.healthAccess == .notAsked
            default: return true
            }
        }
    }
    private var position: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLast: Bool { position == steps.count - 1 }

    /// 選んだジャンルの上位の番組。ジャンルごとに上位3つずつを、順に並べる(1つのジャンルに偏らない)。
    private var picks: [Show] {
        let per = Discover.genreOrder.filter { selected.contains($0) }.map { g in
            Array(Discover.ranked(model.shows.filter { $0.genre == g }).prefix(3))
        }
        var out: [Show] = []
        for i in 0..<3 { for list in per where i < list.count { out.append(list[i]) } }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView { VStack(alignment: .leading, spacing: NCSpace.s5) {
                switch step {
                case .appeal: appeal
                case .understand: understand
                case .genres: genres
                case .shows: shows
                case .health: health
                }
            }
            .padding(NCSpace.s5)
            .frame(maxWidth: .infinity, alignment: .top)
            .id(step) }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .background(Color.nc(.bgBase).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear { selected = model.preferredGenres }
    }

    // MARK: 上部(何ステップ目か、と「スキップ」)

    private var header: some View {
        HStack {
            HStack(spacing: NCSpace.s1) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= position ? Color.nc(.textMain) : Color.nc(.borderControl))
                        .frame(width: i == position ? 20 : 8, height: 8)
                }
            }
            .accessibilityElement().accessibilityLabel("\(steps.count)のうち\(position + 1)")
            Spacer()
            // 説明の2枚だけ、飛ばして設定へ進める。
            if step == .appeal || step == .understand {
                Button { go(.genres) } label: {
                    Text("スキップ").ncText(NCText.body, .textSub).frame(minHeight: NCSize.tapMin)
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(minHeight: NCSize.tapMin)
        .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s3)
        .animation(.snappy(duration: 0.2), value: position)
    }

    // MARK: 1. 魅力

    @ViewBuilder private var appeal: some View {
        Image("LaunchSymbol").resizable().scaledToFit().frame(width: 72, height: 72)
            .padding(.top, NCSpace.s4).accessibilityHidden(true)
        Text("眠りたい夜に、\nちょうどいい番組を").ncText(NCText.title).fixedSize(horizontal: false, vertical: true)
        Text("NeochiPickzz は、ポッドキャストを解析して、寝落ちに向く番組を選べるようにするアプリです。")
            .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: NCSpace.s4) {
            point("moon.zzz", "寝落ちに向く番組だけ", "評点で Z・ZZ・ZZZ の3段階に分けて並べます。")
            point("sparkles", "今夜の1本", "昨夜の結果と好みから、今夜聴く話を提案します。")
            point("timer", "寝落ちの記録", "眠るまでにかかった時間を記録して、朝に振り返れます。")
        }
    }

    // MARK: 2. しくみ

    @ViewBuilder private var understand: some View {
        Text("評点のしくみ").ncText(NCText.title)
        Text("番組の話を、眠りを妨げる要素が少ないかで調べています。")
            .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: NCSpace.s4) {
            point("waveform", "音声を解析", "話す速さ、音量、起伏、興味の度合いを調べます。")
            point("chart.bar", "評点と格付け", "起伏が少なく、耳にゆるく、程よく興味が続く番組ほど高くなります。基準に届かない番組は載せません。")
            point("person.2", "使うほど合っていく", "あなたの寝落ちの記録と、みんなの評価が集まるほど、評点と提案に反映されます。")
        }
        Text("評点は推定で、眠れることを保証するものではありません。医療機器ではありません。")
            .ncText(NCText.footnote, .textSub).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 3. ジャンル

    @ViewBuilder private var genres: some View {
        Text("どんな番組が好きですか").ncText(NCText.title)
        Text("最初に出す番組の選び方に使います。いくつでも選べて、あとから設定で変えられます。")
            .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
        GenreChoiceList(selected: $selected)
    }

    // MARK: 4. 番組

    @ViewBuilder private var shows: some View {
        Text("気になる番組を選びましょう").ncText(NCText.title)
        Text("しおりを付けた番組は、今夜の画面のお気に入りに並びます。あとからでも変えられます。")
            .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
        VStack(spacing: NCSpace.s2) {
            ForEach(picks) { show in
                ScoreRow(show: show, isFavorite: model.favorites.contains(show.id)) { model.toggleFavorite(show) }
            }
        }
    }

    // MARK: 5. ヘルスケア(許可の前の説明)

    @ViewBuilder private var health: some View {
        Image(systemName: "heart.text.square").font(.system(size: 48)).foregroundStyle(Color.nc(.textMain))
            .padding(.top, NCSpace.s4).accessibilityHidden(true)
        Text("寝落ちまでの時間を、\n自動で記録します").ncText(NCText.title).fixedSize(horizontal: false, vertical: true)
        Text("ヘルスケアの睡眠データから、再生を始めてから眠るまでの分数を記録します。次の画面で、読み取りを許可するか選べます。")
            .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: NCSpace.s4) {
            point("bed.double", "読むのは睡眠の記録だけ", "書き込みはしません。")
            point("clock", "ふだんの就寝時刻も自動で", "就寝の時間帯にアプリを開くと、夜の画面を出します。")
            point("lock", "外には出しません", "広告や、第三者への提供には使いません。")
        }
        Text("許可しなくても使えます。そのときは、朝に選択肢で答えて記録できます。あとから設定で変えられます。")
            .ncText(NCText.footnote, .textSub).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 下部のボタン(固定)

    @ViewBuilder private var actions: some View {
        VStack(spacing: NCSpace.s1) {
            if step == .shows && model.favorites.isEmpty {
                // 1つも選んでいないときは副ボタン(枠線)。
                Button { next() } label: {
                    Text("あとで選ぶ").ncText(NCText.body).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                        .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
                }
                .buttonStyle(.pressable)
            } else {
                Button { next() } label: {
                    Text(isLast && step != .health ? "はじめる" : "次へ").ncText(NCText.headline, .bgBase)
                        .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                        .background(Capsule().fill(Color.nc(.textMain)))
                }
                .buttonStyle(.pressable)
                .disabled(requesting)
            }
            // 許可の前の説明には、システムの画面を出さずに離れる手段を置かない(戻るも出さない)。
            if position > 0 && step != .health {
                Button { back() } label: {
                    Text("戻る").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s2)
        .background(Color.nc(.bgBase))
    }

    private func point(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: NCSpace.s3) {
            Image(systemName: icon).font(.system(size: NCSize.iconMd)).frame(width: 28)
                .foregroundStyle(Color.nc(.textMain)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text(title).ncText(NCText.headline)
                Text(body).ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 進む・戻る

    private func go(_ s: Step) {
        if step == .genres { model.savePreferredGenres(selected) }
        withAnimation(.snappy(duration: 0.25)) { step = s }
    }

    private func next() {
        if step == .genres { model.savePreferredGenres(selected) }
        if step == .health {
            requesting = true
            Task { await model.requestHealth(); model.finishOnboarding() }
            return
        }
        if isLast { model.finishOnboarding(); return }
        go(steps[position + 1])
    }

    private func back() { go(steps[max(0, position - 1)]) }
}
