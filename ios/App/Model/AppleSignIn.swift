import Foundation
import CryptoKit
import Security

/// Sign in with Apple のノンス。Apple には SHA256 を渡し、Supabase には元の文字列を渡す(トークンの使い回しを防ぐ)。
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        while out.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if byte < chars.count * (256 / chars.count) { out.append(chars[Int(byte) % chars.count]) }  // 偏りを避ける
        }
        return out
    }
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
