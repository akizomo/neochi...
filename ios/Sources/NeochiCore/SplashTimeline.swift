import Foundation

/// 起動画面のアニメーション。N が右下の角を軸に倒れて Z になり、小さい z が浮かんで消える。
/// 時刻(秒)から、角度・濃さ・位置を求めるだけで、画面の描き方には依らない(Linux でもテストできる)。
/// 長さの単位は、ロゴの SVG と同じ(N の高さを 698 とする)。位置は N の右下の角(倒れる軸)からの距離。
public enum SplashTimeline {
    public static let fallStart = 0.8        // 倒れ始め(秒)
    public static let fallDuration = 1.4
    public static let fallAngle = 90.0       // 時計回り
    public static let fadeStart = 4.8        // 最初の画面へ切り替え始める
    public static let total = 5.2
    public static let reducedFadeStart = 0.8 // 視差効果を減らす: 動かさず、N を見せるだけ
    public static let reducedTotal = 1.2
    public static let wordmarkFadeIn = 0.6   // 下のワードマークが現れるまで

    public struct Floater: Equatable, Sendable {
        public let start: Double
        public let duration: Double
        public let scale: Double   // z の大きさ(N と同じ単位に対する倍率)
        public let x: Double       // 軸からの横の位置
        public let y: Double       // 軸からの縦の位置(上が負)
    }

    public static let floaters: [Floater] = [
        Floater(start: 2.5, duration: 1.8, scale: 0.30, x: 642, y: -700),
        Floater(start: 3.1, duration: 1.8, scale: 0.22, x: 782, y: -900),
    ]
    public static let floatRise = 120.0     // 消えるまでに上がる高さ
    public static let floatPeak = 0.6       // 濃さの最大

    /// 加速してから減速する(cubic in-out)。範囲外は 0〜1 に収める。
    public static func ease(_ p: Double) -> Double {
        let p = min(max(p, 0), 1)
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// N の傾き(度)。
    public static func angle(at t: Double, reduceMotion: Bool = false) -> Double {
        reduceMotion ? 0 : fallAngle * ease((t - fallStart) / fallDuration)
    }

    public static func progress(_ f: Floater, at t: Double) -> Double {
        min(max((t - f.start) / f.duration, 0), 1)
    }

    /// 小さい z の濃さ。40% のところで最大になり、そこから消える。
    public static func opacity(_ f: Floater, at t: Double, reduceMotion: Bool = false) -> Double {
        if reduceMotion { return 0 }
        let p = progress(f, at: t)
        return (p < 0.4 ? p / 0.4 : 1 - (p - 0.4) / 0.6) * floatPeak
    }

    public static func rise(_ f: Floater, at t: Double) -> Double { progress(f, at: t) * floatRise }

    /// 画面全体の濃さ。終わりに近づくと、最初の画面へ溶ける。
    public static func screenOpacity(at t: Double, reduceMotion: Bool = false) -> Double {
        let (from, to) = reduceMotion ? (reducedFadeStart, reducedTotal) : (fadeStart, total)
        return t <= from ? 1 : max(0, 1 - (t - from) / (to - from))
    }

    public static func wordmarkOpacity(at t: Double) -> Double { min(max(t / wordmarkFadeIn, 0), 1) }

    public static func duration(reduceMotion: Bool = false) -> Double { reduceMotion ? reducedTotal : total }
}
