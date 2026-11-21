import Foundation

/// ヘルスケアの入眠の時刻を、その晩の再生の「寝落ち」とみなしてよいか。
///
/// 再生を始めてから寝るまでに聴くのをやめていたら(夕方に試しで聴いた、など)、その入眠は、聴きながらの寝落ちではない。
/// 音が最後に鳴っていた時刻から、`graceAfterPlayback` より後の入眠は、寝落ちとみなさない。
/// 再生の終わり方。眠った人は再生を止められないので、自分で止めた晩は、聴きながら眠った晩ではない。
public enum PlaybackEnding: String, Codable, Sendable {
    /// 最後まで流れた、またはスリープタイマーが切れた。
    case natural
    /// 自分で止めた(一時停止、「終わる」)。
    case manual
}

public enum SleepAttribution {
    /// 音が止まってから、この時間までの入眠は、寝落ちとみなす(入眠の判定のずれと、止まったあとに眠る分を見込む)。
    public static let graceAfterPlayback: TimeInterval = 30 * 60

    public enum Result: Equatable, Sendable {
        /// 寝落ちとみなす入眠。
        case onset(Date)
        /// 入眠は記録されていたが、音が止まってから時間がたっていた(聴きながら寝ていない)。
        case afterPlayback
        /// 入眠の記録がない(まだ同期されていない、ヘルスケアの許可がない、など)。
        case unknown
    }

    /// 入眠が分からないとき、聴きながら眠った晩ではないとして、振り返りを出さずに捨てるか。
    /// 自分で止めた晩は、ヘルスケアの睡眠データが入る人なら、入眠の記録を待つ(止めたあとの30分以内に眠ったかもしれない)。
    /// 睡眠データがない人は、待つ先がないので捨てる。最後まで流れた晩、アプリが落ちた晩(終わり方が不明)は捨てない。
    public static func dropsWithoutOnset(ending: PlaybackEnding?, hasHealthData: Bool) -> Bool {
        ending == .manual && !hasHealthData
    }

    /// - Parameters:
    ///   - onset: ヘルスケアの入眠の時刻(再生の開始以降で、最初のもの)。
    ///   - lastAudible: 音が最後に鳴っていた時刻。nil は分からない(前の版で残った晩)ので、入眠をそのまま使う。
    public static func judge(onset: Date?, lastAudible: Date?) -> Result {
        guard let onset else { return .unknown }
        if let lastAudible, onset > lastAudible.addingTimeInterval(graceAfterPlayback) { return .afterPlayback }
        return .onset(onset)
    }
}
