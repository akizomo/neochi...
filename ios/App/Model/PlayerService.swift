import AVFoundation
import MediaPlayer
import Observation
import UIKit
import os

/// 再生の状態。画面は、これを見て出し分ける(読み込み中の表示、失敗時の「もう一度」)。
enum PlaybackState: Equatable {
    case idle
    /// 読み込み中・通信待ち(回線が細いとき、途中でも戻る)。
    case loading
    case playing
    case paused
    /// 再生できなかった(URLが壊れている、通信が切れたまま戻らない、など)。
    case failed
}

/// 再生。バックグラウンドで再生し、ロック画面には回のタイトル・番組名と再生/一時停止だけを出す。
/// 夜の画面には、経過と長さを「12:34 / 42:10」の文字で出す。シークバー、シーク、スキップは出さない。
///
/// 夜に、気づかないうちに止まっていた、が一番困る。次の3つを守る:
/// - 電話・アラーム・Siri などで中断されたら止まった状態を画面に出し、終わったら(システムが許せば)自動で再開する
/// - 読み込みや通信待ちは、画面に出す。長く戻らないときは、失敗として「もう一度」を出す
/// - 実際の再生の状態(AVPlayer)を見て、画面の状態を合わせる(押した記録だけを信じない)
@MainActor
@Observable
final class PlayerService {
    private(set) var state: PlaybackState = .idle
    /// 再生する意思がある間(読み込み中を含む)。再生/一時停止ボタンの絵に使う。
    var isPlaying: Bool { state == .playing || state == .loading }
    /// スリープタイマー(分)。0 = なし(回の最後まで再生して止まる)。
    var timerMinutes = 0 { didSet { restartTimer() } }
    /// 経過(秒)。1秒ごとに更新する。
    private(set) var elapsedSec: Double = 0
    /// 長さ(秒)。音声から分かったときだけ入る(番組の情報に長さがないときの補い)。
    private(set) var loadedDurationSec: Double?
    /// 音が鳴っている間、1秒ごとに呼ぶ(朝の振り返りで、音が最後に鳴っていた時刻を知るため)。
    var onAudible: ((Date) -> Void)?

    private var player: AVPlayer?
    private var observers: [NSKeyValueObservation] = []
    /// 回ごとの通知(終わり・失敗)。回が変わるたびに外す。
    private var itemNotifications: [NSObjectProtocol] = []
    /// ずっと持つ通知(中断など)。
    private var sessionNotifications: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var timerTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// やり直し用。
    private var lastURL: URL?
    private var lastTitle = ""
    private var lastSubtitle: String?
    private var remoteReady = false

    /// 読み込みがこの秒数を超えて戻らなければ、失敗とみなす。
    private let loadTimeout: Double = 25

    init() {
        let nc = NotificationCenter.default
        // 電話・アラーム・Siri などによる中断。終わって、システムが「再開してよい」と言ったら、再開する。
        sessionNotifications.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let opts = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            Task { @MainActor in self?.handleInterruption(type, opts) }
        })
        // メディアサービスが落ちて作り直されたとき(まれ)。
        sessionNotifications.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recoverFromReset() }
        })
    }

    /// 音声URLがない(サンプル)ときは、音を出さず、状態だけを進める。
    /// title は回のタイトル、subtitle は番組名(ロック画面の2行目)。
    func start(url: URL?, title: String, subtitle: String? = nil) {
        stop()
        lastURL = url; lastTitle = title; lastSubtitle = subtitle
        setUpNowPlaying(title: title, subtitle: subtitle)
        setUpRemoteCommands()
        guard let url else { state = .playing; restartTimer(); return }
        state = .loading
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            state = .failed; return
        }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = 0
        player = p
        observe(p, item)
        p.play()
        startWatchdog()
        restartTimer()
    }

    func pause() {
        guard state != .idle, state != .failed else { return }
        state = .paused
        player?.pause()
        updateNowPlayingRate(0)
    }

    func resume() {
        if state == .failed { retry(); return }
        guard state != .idle else { return }
        state = player == nil ? .playing : .loading
        player?.play()
        fade(to: 1, seconds: 1)
        startWatchdog()
        updateNowPlayingRate(1)
    }

    func toggle() { isPlaying ? pause() : resume() }

    /// 指定の秒から聴く。再生中でも一時停止中でも使える。
    func seek(to seconds: Double) {
        guard let player, state != .failed, state != .idle else { return }
        let t = max(0, seconds)
        elapsedSec = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// いまの位置から、指定の秒だけ戻る・進む(15秒の送り・戻し)。長さが分かっていれば、終わりの手前で止める。
    func skip(by seconds: Double) {
        var t = elapsedSec + seconds
        if let d = loadedDurationSec, d > 1 { t = min(t, d - 1) }
        seek(to: t)
    }

    /// 失敗したあと、同じ回をもう一度。
    func retry() {
        guard state == .failed || state == .idle else { return }
        start(url: lastURL, title: lastTitle, subtitle: lastSubtitle)
    }

    func stop() {
        timerTask?.cancel(); fadeTask?.cancel(); watchdog?.cancel()
        observers.forEach { $0.invalidate() }; observers = []
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }; itemNotifications = []
        if let timeObserver { player?.removeTimeObserver(timeObserver) }; timeObserver = nil
        player?.pause(); player = nil
        elapsedSec = 0; loadedDurationSec = nil
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: 実際の再生の状態を見る

    private func observe(_ p: AVPlayer, _ item: AVPlayerItem) {
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                if t.seconds.isFinite { self.elapsedSec = t.seconds }
                if self.state == .playing { self.onAudible?(Date()) }
                let d = item.duration.seconds
                if d.isFinite, d > 0, self.loadedDurationSec == nil { self.loadedDurationSec = d }
            }
        }
        observers = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, self.player?.currentItem === item else { return }
                    if item.status == .failed { self.fail() }
                }
            },
            p.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
                Task { @MainActor in self?.sync(p) }
            },
        ]
        let nc = NotificationCenter.default
        itemNotifications = [
            nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            },
            nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.fail() }
            },
        ]
    }

    /// AVPlayer の状態に、画面の状態を合わせる。
    private func sync(_ p: AVPlayer) {
        guard player === p, state != .failed, state != .idle else { return }
        switch p.timeControlStatus {
        case .playing:
            watchdog?.cancel()
            if state != .playing { state = .playing; fade(to: 1, seconds: 3); updateNowPlayingRate(1) }
        case .waitingToPlayAtSpecifiedRate:
            if state == .playing { state = .loading }   // 途中で通信待ちになった
        case .paused:
            // 押していないのに止まった(中断・ヘッドホンが抜けた、など)。止まったと、画面に出す。
            if state == .playing { state = .paused; updateNowPlayingRate(0) }
        @unknown default: break
        }
    }

    private static let log = Logger(subsystem: "neochi", category: "player")

    private func fail() {
        // 原因を残す(実機で止まったとき、あとから調べられるように)。
        let item = player?.currentItem
        let events = item?.errorLog()?.events.suffix(3).map { "\($0.errorStatusCode) \($0.errorComment ?? "-") \($0.uri ?? "-")" } ?? []
        Self.log.error("再生に失敗: url=\(self.lastURL?.absoluteString ?? "-", privacy: .public) error=\(item?.error?.localizedDescription ?? "なし", privacy: .public) timeControl=\(self.player?.timeControlStatus.rawValue ?? -1) reason=\(self.player?.reasonForWaitingToPlay?.rawValue ?? "-", privacy: .public) log=\(events.joined(separator: " | "), privacy: .public)")
        watchdog?.cancel(); fadeTask?.cancel()
        player?.pause()
        state = .failed
        updateNowPlayingRate(0)
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let seconds = loadTimeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { if self?.state == .loading { self?.fail() } }
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, _ options: AVAudioSession.InterruptionOptions?) {
        switch type {
        case .began:
            if state == .playing || state == .loading { state = .paused; updateNowPlayingRate(0) }
        case .ended:
            // 電話が終わった、など。システムが再開を許したときだけ、自動で再開する。
            if options?.contains(.shouldResume) == true, state == .paused, player != nil {
                try? AVAudioSession.sharedInstance().setActive(true)
                resume()
            }
        default: break
        }
    }

    private func recoverFromReset() {
        guard player != nil else { return }
        fail()
    }

    // MARK: スリープタイマー: 切れたら、音量を数秒かけて下げてから止める(突然止めない)

    private func restartTimer() {
        timerTask?.cancel()
        guard timerMinutes > 0, isPlaying else { return }
        let seconds = Double(timerMinutes) * 60
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.fadeOutAndStop()
        }
    }

    private func fadeOutAndStop() async {
        fade(to: 0, seconds: 8)
        try? await Task.sleep(for: .seconds(8))
        stop()
    }

    private func fade(to target: Float, seconds: Double) {
        fadeTask?.cancel()
        guard let player else { return }
        let start = player.volume
        let steps = 20
        fadeTask = Task { [weak player] in
            for i in 1...steps {
                guard !Task.isCancelled, let player else { return }
                player.volume = start + (target - start) * Float(i) / Float(steps)
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
            }
        }
    }

    // MARK: ロック画面

    private func setUpNowPlaying(title: String, subtitle: String?) {
        let size = CGSize(width: 600, height: 600) // ロック画面の画像の生成サイズ(画面の寸法ではない)
        let night = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 11 / 255, green: 13 / 255, blue: 18 / 255, alpha: 1).setFill()   // bg-night の無地
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: size) { _ in night },
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            // 経過時間と長さは入れない(入れるとロック画面に進捗とシークバーが出る)
        ]
        if let subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingRate(_ rate: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 開始のたびに足すと、同じ操作が重なって呼ばれる。一度だけ設定する。
    private func setUpRemoteCommands() {
        guard !remoteReady else { return }
        remoteReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.isEnabled = true
        c.pauseCommand.isEnabled = true
        c.togglePlayPauseCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        for cmd in [c.nextTrackCommand, c.previousTrackCommand, c.skipForwardCommand, c.skipBackwardCommand,
                    c.seekForwardCommand, c.seekBackwardCommand] as [MPRemoteCommand] { cmd.isEnabled = false }
        c.changePlaybackPositionCommand.isEnabled = false
    }
}
