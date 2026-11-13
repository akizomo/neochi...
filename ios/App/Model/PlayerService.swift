import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// 再生。バックグラウンドで再生し、ロック画面には番組名と再生/一時停止だけを出す。
/// 進捗、残り時間、シーク、スキップは出さない(夜の画面の方針)。
@MainActor
@Observable
final class PlayerService {
    private(set) var isPlaying = false
    /// スリープタイマー(分)。0 = なし(回の最後まで再生して止まる)。
    var timerMinutes = 0 { didSet { restartTimer() } }

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timerTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?

    /// 音声URLがない(サンプル)ときは、音を出さず、状態だけを進める。
    func start(url: URL?, title: String) {
        stop()
        isPlaying = true
        setUpNowPlaying(title: title)
        setUpRemoteCommands()
        guard let url else { restartTimer(); return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = 0
        player = p
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
        fade(to: 1, seconds: 3)
        restartTimer()
    }

    func pause() { isPlaying = false; player?.pause() }
    func resume() { isPlaying = true; player?.play(); fade(to: 1, seconds: 1) }
    func toggle() { isPlaying ? pause() : resume() }

    func stop() {
        timerTask?.cancel(); fadeTask?.cancel()
        player?.pause(); player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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

    private func setUpNowPlaying(title: String) {
        let size = CGSize(width: 600, height: 600)
        let night = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 11 / 255, green: 13 / 255, blue: 18 / 255, alpha: 1).setFill()   // bg-night の無地
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: size) { _ in night },
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            // 経過時間と長さは入れない(入れるとロック画面に進捗とシークバーが出る)
        ]
    }

    private func setUpRemoteCommands() {
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
