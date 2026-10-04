import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class BriefingPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var articles: [ReaderArticle] = []
    @Published private(set) var index = 0
    @Published private(set) var playing = false
    @Published private(set) var preparing = false
    @Published var voice: BriefingVoice = VoicePreferences.selected {
        didSet {
            UserDefaults.standard.set(voice.rawValue, forKey: "briefingVoice")
            UserDefaults.standard.set(true, forKey: "geminiVoicePreferenceV1")
            pendingPosition = 0; heardSeconds = []; position = 0
            let restart = playing || preparing
            resetAudio()
            if restart { speakCurrent() }
        }
    }
    @Published var error: String?
    @Published var rate: Double = UserDefaults.standard.object(forKey: "speechRate") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(rate, forKey: "speechRate")
            if let audioPlayer { audioPlayer.rate = Float(rate); nowPlaying() }
            else if playing { speakCurrent() } else if current != nil { currentUtterance = nil; synth.stopSpeaking(at: .immediate) }
        }
    }
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var sleepMinutes = 0 { didSet { sleepDeadline = sleepMinutes > 0 ? Date().addingTimeInterval(Double(sleepMinutes * 60)) : nil } }
    @Published var stopAfterArticle = false
    private var sleepDeadline: Date?
    private var timer: Timer?
    private var pendingPosition: Double = 0
    private var heardSeconds = Set<Int>()
    private var lastTick: Double?
    private struct Checkpoint: Codable { let articles: [ReaderArticle]; let index: Int; let position: Double; let voice: String; let heard: Set<Int> }
    private let checkpointKey = "playbackCheckpointV1"
    var canSeek: Bool { audioPlayer != nil && duration > 0 }
    var onListenedArticle: ((ReaderArticle) -> Void)?
    var onFinishedArticle: ((ReaderArticle) -> Void)?
    var onFinishedBriefing: ((String) -> Void)?
    private let synth = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var audioPlayer: AVAudioPlayer?
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var resumeAfterInterruption = false
    private var completesBriefing = false
    var current: ReaderArticle? { articles.indices.contains(index) ? articles[index] : nil }
    func adoptGeminiDefaultIfAvailable(_ articles: [ReaderArticle]) {
        guard !UserDefaults.standard.bool(forKey: "geminiVoicePreferenceV1"),
              !playing, !preparing,
              !articles.isEmpty, articles.allSatisfy({ $0.audio?[BriefingVoice.gemini.rawValue].flatMap(WebURL.parse)?.scheme == "https" }) else { return }
        voice = .gemini
    }
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: checkpointKey), let saved = try? JSONDecoder().decode(Checkpoint.self, from: data), saved.articles.indices.contains(saved.index), saved.voice == voice.rawValue {
            articles = saved.articles; index = saved.index; pendingPosition = saved.position; position = saved.position; heardSeconds = saved.heard
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        synth.delegate = self; synth.usesApplicationAudioSession = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commands = MPRemoteCommandCenter.shared()
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(by: 15) }; return .success }
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(by: -15) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }; return .success
        }
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(1) }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-1) }; return .success }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.resumeAfterInterruption = self.playing; self.pause() }
                else if self.resumeAfterInterruption, let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.resume() }
            }
        }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        }
    }
    func start(_ articles: [ReaderArticle], at index: Int = 0, completesBriefing: Bool = false) {
        guard articles.indices.contains(index) else { return }
        pendingPosition = 0; position = 0; heardSeconds = []; lastTick = nil
        self.articles = articles; self.index = index; self.completesBriefing = completesBriefing && index == 0; speakCurrent(); UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func activate() -> Bool {
        do { let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true); return true }
        catch { self.error = "音声を開始できませんでした。再生をやり直してください。"; playing = false; return false }
    }
    private func speakCurrent() {
        resetAudio(); error = nil
        guard let current, activate() else { return }
        if voice != .device { prepareRemoteAudio(current); return }
        let utterance = AVSpeechUtterance(string: current.speechText)
        let voiceID = UserDefaults.standard.string(forKey: "speechVoice") ?? ""
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) ?? AVSpeechSynthesisVoice(language: "ja-JP")
        guard utterance.voice != nil else { error = "日本語音声が見つかりません。iOSの設定で日本語の読み上げ音声をダウンロードしてください。"; return }
        utterance.rate = Float(rate) * AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = utterance; playing = true; synth.speak(utterance); nowPlaying()
    }
    private func resetAudio() {
        generation = UUID(); preparation?.cancel(); preparation = nil; preparing = false
        lastTick = nil; duration = 0
        currentUtterance = nil; synth.stopSpeaking(at: .immediate)
        audioPlayer?.stop(); audioPlayer = nil; playing = false
    }
    private func prepareRemoteAudio(_ article: ReaderArticle) {
        guard let url = article.audio?[voice.rawValue].flatMap(WebURL.parse) else {
            error = "\(voice.shortName)の音声は、この配信分にはまだ用意されていません。音声が配信されたあとに再取得するか、プルダウンでiPhoneの標準音声を選択してください。"
            return
        }
        let token = generation, selected = voice
        preparing = true
        preparation = Task { @MainActor in
            do {
                await AudioCache.shared.protect(url)
                let file = try await AudioCache.shared.verifiedFile(for: url, metadata: article.audioMetadata?[selected.rawValue])
                guard !Task.isCancelled, token == generation else { return }
                let audio: AVAudioPlayer
                do { audio = try AVAudioPlayer(contentsOf: file) }
                catch { await AudioCache.shared.invalidate(url); throw error }
                audio.delegate = self; audio.enableRate = true; audio.rate = Float(rate)
                audioPlayer = audio; audio.prepareToPlay()
                duration = audio.duration; audio.currentTime = min(pendingPosition, max(0, audio.duration - 0.1)); pendingPosition = 0; position = audio.currentTime; lastTick = nil
                await AudioCache.shared.protect(url)
                playing = audio.play(); preparing = false
                if !playing { error = "音声を再生できませんでした。もう一度再生してください。" }
                nowPlaying()
                let upcoming = articles.dropFirst(index + 1).compactMap { $0.audio?[selected.rawValue].flatMap(WebURL.parse) }
                await AudioCache.shared.prefetch(upcoming)
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                preparing = false; playing = false
                self.error = "\(selected.shortName)の音声を取得できませんでした。初回の音声取得には通信が必要です。ダウンロード済みの音声はオフラインで再生できます。"
            }
        }
    }
    func pause() {
        if preparing { preparation?.cancel(); preparation = nil; preparing = false; generation = UUID() }
        checkpoint(); lastTick = nil
        audioPlayer?.pause(); synth.pauseSpeaking(at: .immediate); playing = false; nowPlaying()
    }
    func resume() {
        guard current != nil, activate() else { return }
        if let audioPlayer { playing = audioPlayer.play(); nowPlaying() }
        else if synth.isPaused { playing = synth.continueSpeaking(); nowPlaying() } else { speakCurrent() }
    }
    func toggle() { playing ? pause() : resume() }
    func skip(_ offset: Int) {
        guard !articles.isEmpty else { return }
        let next = index + offset
        guard articles.indices.contains(next) else { return }
        completesBriefing = false; pendingPosition = 0; heardSeconds = []; index = next; speakCurrent()
    }
    func stop() {
        resetAudio(); articles = []; index = 0; position = 0; duration = 0; pendingPosition = 0; lastTick = nil
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        Task { await AudioCache.shared.protect(nil) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finished(utterance) }
    }
    private func finished(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }; advance()
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, player === self.audioPlayer else { return }
            if flag { self.advance() } else { self.playing = false; self.error = "音声の再生が中断されました。再生をやり直してください。" }
        }
    }
    private func advance() {
        guard let article = current else { return }
        tick()
        if voice == .device || (duration > 0 && Double(heardSeconds.count) / duration >= 0.9) { onListenedArticle?(article) }
        onFinishedArticle?(article)
        if stopAfterArticle {
            stopAfterArticle = false; resetAudio(); pendingPosition = 0; position = 0; heardSeconds = []
            if index + 1 < articles.count { index += 1; checkpoint() } else { stop() }; return
        }
        heardSeconds = []; pendingPosition = 0; lastTick = nil
        if index + 1 < articles.count { index += 1; speakCurrent() }
        else { if completesBriefing { onFinishedBriefing?(article.digestDate) }; stop() }
    }
    func checkpoint() {
        guard current != nil else { return }
        let value = Checkpoint(articles: articles, index: index, position: audioPlayer?.currentTime ?? pendingPosition, voice: voice.rawValue, heard: heardSeconds)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: checkpointKey) }
    }
    func seek(by seconds: Double) { seek(to: position + seconds) }
    func seek(to seconds: Double) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = min(max(0, seconds), max(0, audioPlayer.duration - 0.05))
        position = audioPlayer.currentTime; lastTick = nil; checkpoint(); nowPlaying()
    }
    private func tick() {
        if let deadline = sleepDeadline, Date() >= deadline { sleepMinutes = 0; pause() }
        guard let audioPlayer else { return }
        let currentTime = audioPlayer.currentTime
        if playing, let previous = lastTick, currentTime >= previous, currentTime - previous < 4 {
            for second in Int(previous)..<Int(currentTime) { heardSeconds.insert(second) }
        }
        lastTick = playing ? currentTime : nil; position = currentTime; duration = audioPlayer.duration
        if playing { checkpoint(); nowPlaying() }
    }
    private func nowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: "AIダイジェスト · \(index + 1)/\(articles.count)", MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0, MPNowPlayingInfoPropertyDefaultPlaybackRate: rate, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if let audioPlayer {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = audioPlayer.duration
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer.currentTime
        }
    }
}
