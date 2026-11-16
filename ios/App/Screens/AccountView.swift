import SwiftUI
import AuthenticationServices
import NeochiCore

/// アカウント。匿名のまま使い始め、Apple に連携すると、機種変更でも記録を引き継げる。
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var info: SupabaseClient.AccountInfo?
    @State private var nonce = AppleNonce.random()
    @State private var message: String?
    @State private var working = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    private var linked: Bool { info?.providers.contains("apple") == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s4) {
                    if !SupabaseClient.shared.isConfigured {
                        note("接続先が設定されていないので、記録はこの端末だけに残ります。")
                    } else if info == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if linked {
                        linkedSection
                    } else {
                        anonymousSection
                    }
                    if let message { Text(message).ncText(NCText.footnote, .textSub) }
                }
                .padding(.horizontal, NCSpace.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.nc(.bgBase))
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .task { await reload() }
            .confirmationDialog("ログアウトしますか", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) { Task { await signOut() } }
            } message: { Text("もう一度 Apple でログインすると、記録は戻ります。") }
            .confirmationDialog("アカウントを削除しますか", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { Task { await delete() } }
            } message: { Text("寝落ちの記録がすべて消えます。元に戻せません。") }
        }
    }

    private var anonymousSection: some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            note("いまは、この端末だけで記録しています。Apple でログインすると、機種変更や入れ直しのあとも、記録を引き継げます。")
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
                request.nonce = AppleNonce.sha256(nonce)
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(working)
        }
    }

    private var linkedSection: some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("ログイン中").ncText(NCText.footnote, .textSub)
                Text("Apple").ncText(NCText.headline)
                if let mail = info?.email, !mail.isEmpty { Text(mail).ncText(NCText.footnote, .textSub) }
            }
            .padding(NCSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
            Button("ログアウト") { confirmSignOut = true }.buttonStyle(.pressable).disabled(working)
            Button("アカウントを削除", role: .destructive) { confirmDelete = true }.buttonStyle(.pressable).disabled(working)
        }
    }

    private func note(_ t: String) -> some View { Text(t).ncText(NCText.footnote, .textSub) }

    private func reload() async {
        guard SupabaseClient.shared.isConfigured else { return }
        do { info = try await SupabaseClient.shared.account() }
        catch { message = "状態を読み込めませんでした。通信を確かめて、もう一度開いてください。" }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        working = true; defer { working = false; nonce = AppleNonce.random() }
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { message = "Apple のログインを完了できませんでした。" }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
                message = "Apple のログインを完了できませんでした。"; return
            }
            do {
                let r = try await SupabaseClient.shared.linkApple(idToken: token, nonce: nonce)
                message = r == .restored ? "前のアカウントに、ログインし直しました。" : nil
                await reload()
            } catch { message = "ログインを完了できませんでした。しばらくしてから、もう一度お試しください。" }
        }
    }

    private func signOut() async {
        working = true; defer { working = false }
        await SupabaseClient.shared.signOut()
        info = nil; await reload()
    }

    private func delete() async {
        working = true; defer { working = false }
        do { try await SupabaseClient.shared.deleteAccount(); info = nil; message = "アカウントを削除しました。"; await reload() }
        catch { message = "削除できませんでした。しばらくしてから、もう一度お試しください。" }
    }
}

/// 自分タブの先頭に置くアカウントのカード。匿名のあいだは、連携をすすめる言葉を出す。
struct AccountRow: View {
    var tick = 0   // 画面を閉じたあとに増やすと、状態を読み直す
    let action: () -> Void
    @State private var info: SupabaseClient.AccountInfo?

    private var linked: Bool { info?.providers.contains("apple") == true }

    var body: some View {
        if SupabaseClient.shared.isConfigured {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: NCSpace.s1) {
                        Text("アカウント").ncText(NCText.footnote, .textSub)
                        Text(linked ? "Apple でログイン中" : "記録を引き継ぐ").ncText(NCText.headline)
                        if !linked && info != nil {
                            Text("Apple でログインすると、機種変更のあとも記録が残ります。").ncText(NCText.footnote, .textSub)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").ncText(NCText.footnote, .textSub)
                }
                .padding(NCSpace.s4)
                .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
            }
            .buttonStyle(.pressable)
            .task(id: tick) { info = try? await SupabaseClient.shared.account() }
        }
    }
}
