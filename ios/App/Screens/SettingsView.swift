import SwiftUI
import NeochiCore

/// 設定。自分タブの記録と分けて、アプリの設定だけを置く。
/// 上から: 睡眠(就寝時刻・ヘルスケア)、好み、アカウント(1.0 は出さない)、データ、このアプリについて。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var editingBedtime = false
    @State private var editingGenres = false
    @State private var showingAccount = false
    @State private var accountTick = 0
    @State private var confirmDeleteAll = false
    @State private var deleteError = false

    private static let privacyURL = URL(string: "https://neochipickzz.vercel.app/privacy.html")!
    private static let siteURL = URL(string: "https://neochipickzz.vercel.app/")!

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(v)(\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NCSpace.s3) {
                header("睡眠")
                bedtimeRow
                healthRow
                header("好み")
                genreRow
                if AccountFeature.enabled {
                    header("アカウント")
                    AccountRow(tick: accountTick) { showingAccount = true }
                }
                header("データ")
                dataRow
                header("このアプリについて")
                aboutRows
            }
            .padding(.horizontal, NCSpace.s5)
            .padding(.bottom, NCSpace.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.nc(.bgBase))
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("記録をすべて削除しますか", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                Task { do { try await model.deleteAllRecords(); deleteError = false } catch { deleteError = true } }
            }
        } message: { Text("この端末とサーバーの、寝落ちの記録がすべて消えます。元に戻せません。") }
        .sheet(isPresented: $showingAccount, onDismiss: { accountTick += 1 }) { AccountView() }
        .sheet(isPresented: $editingGenres) { GenrePreferenceView(editing: true) }
        .sheet(isPresented: $editingBedtime) { BedtimeSetupView(editing: true, initial: model.bedtimeMinute) }
        .task { await model.refreshHealthAccess() }
    }

    private func header(_ t: String) -> some View {
        Text(t).ncText(NCText.headline).padding(.top, NCSpace.s4)
    }

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

    /// ヘルスケア(睡眠データ)の許可。最初に許可しなかった人が、あとから変えられる入口。
    /// 読み取りの許可が「あるか」は、アプリからは分からない。聞いていなければ許可画面を出し、聞いたあとは、ヘルスケアで変えてもらう。
    @ViewBuilder private var healthRow: some View {
        if model.healthAccess != .unavailable {
            let notAsked = model.healthAccess == .notAsked
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                Text("ヘルスケア(睡眠データ)").ncText(NCText.footnote, .textSub)
                Text(notAsked ? "まだ許可していません。許可すると、寝落ちまでの分数を自動で記録できます。"
                              : "許可を変えるときは、ヘルスケアのプロフィールから、NeochiPickzz の睡眠を選んでください。")
                    .ncText(NCText.body).fixedSize(horizontal: false, vertical: true)
                Button {
                    if notAsked { Task { await model.requestHealth() } }
                    else if let u = URL(string: "x-apple-health://") { openURL(u) }
                } label: {
                    Text(notAsked ? "許可する" : "ヘルスケアを開く").ncText(NCText.headline, .bgBase)
                        .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                        .background(Capsule().fill(Color.nc(.textMain)))
                }
                .buttonStyle(.pressable)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
    }

    /// 好みのジャンル(最初に聞いたもの)。記録がたまるまでの、最初の番組と並びに使う。
    private var genreRow: some View {
        let names = Discover.genreOrder.filter { model.preferredGenres.contains($0) }
        return Button { editingGenres = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("好みのジャンル").ncText(NCText.footnote, .textSub)
                    Text(names.isEmpty ? "未設定" : names.joined(separator: "・")).ncText(NCText.body).lineLimit(1)
                }
                Spacer()
                HStack(spacing: NCSpace.s1) { Text("変える"); Image(systemName: "chevron.right") }.ncText(NCText.footnote, .textSub)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.pressable)
    }

    /// データの削除。サーバーの記録を先に消し、消せたら端末の記録も消す。
    private var dataRow: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Button(role: .destructive) { confirmDeleteAll = true } label: {
                HStack {
                    Text("記録をすべて削除").ncText(NCText.body)
                    Spacer()
                }
                .padding(NCSpace.s4)
                .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
            }
            .buttonStyle(.pressable)
            Text("アプリを消しても、サーバーの記録は残ります。消したいときは、先にここで削除してください。")
                .ncText(NCText.footnote, .textSub).fixedSize(horizontal: false, vertical: true)
            if deleteError { Text("削除できませんでした。通信を確かめて、もう一度お試しください。").ncText(NCText.footnote, .textSub) }
        }
    }

    private var aboutRows: some View {
        VStack(spacing: NCSpace.s2) {
            linkRow("プライバシーポリシー", Self.privacyURL)
            linkRow("紹介サイト", Self.siteURL)
            HStack {
                Text("バージョン").ncText(NCText.body)
                Spacer()
                Text(version).ncText(NCText.body, .textSub).monospacedDigit()
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
    }

    private func linkRow(_ title: String, _ url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack {
                Text(title).ncText(NCText.body)
                Spacer()
                Image(systemName: "arrow.up.right").ncText(NCText.footnote, .textSub)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.pressable)
    }
}
