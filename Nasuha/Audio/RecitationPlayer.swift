import AVFoundation
import MediaPlayer
import NasuhaCore
import SwiftUI

/// Plays per-ayah recordings one after another, and reports which ayah is being recited
/// so screens can follow along. Audio is offered only when a reciter's licence is cleared.
@MainActor
@Observable
final class RecitationPlayer {
    enum Status: Equatable {
        case idle, loading, playing, paused, failed
    }

    private(set) var status: Status = .idle
    /// The ayah being recited now.
    private(set) var currentKey: AyahKey?
    private(set) var plan: PlaybackPlan?
    private(set) var reciter: Reciter?

    /// Called with the seconds listened each time an ayah finishes.
    @ObservationIgnored var onListened: ((Double) -> Void)?
    /// Gives the Now Playing title for an ayah, e.g. "Ad-Duha 93:3".
    @ObservationIgnored var titleFor: (AyahKey) -> String = { $0.description }

    @ObservationIgnored private let catalog: ReciterCatalog
    @ObservationIgnored private let cache: AudioCache
    @ObservationIgnored private let includeUncleared: Bool
    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var sequence: [AyahKey] = []
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var enqueued = 0
    @ObservationIgnored private var wantsPlaying = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loader: Task<Void, Never>?
    @ObservationIgnored private var positions: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteCommandsReady = false

    /// How many recordings to keep ready ahead of the one playing.
    private static let lookahead = 3

    init(catalog: ReciterCatalog, cache: AudioCache = AudioCache(root: AudioCache.defaultRoot())) {
        self.catalog = catalog
        self.cache = cache
        includeUncleared = Self.previewEnabled
        reciter = catalog.reciter(preferred: nil, includeUncleared: includeUncleared)
        player.actionAtItemEnd = .advance
        observe()
    }

    /// Debug builds can turn audio on for testing with the launch argument `-audioPreview YES`.
    /// Release builds never play a reciter whose licence is not cleared.
    private static var previewEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "audioPreview")
        #else
        false
        #endif
    }

    /// False hides every play button in the app.
    var isAvailable: Bool { reciter != nil }

    var isPlaying: Bool { status == .playing || status == .loading }

    func selectReciter(id: String?) {
        let next = catalog.reciter(preferred: id, includeUncleared: includeUncleared)
        if next != reciter {
            stop()
            reciter = next
        }
    }

    // MARK: Controls

    func play(_ plan: PlaybackPlan) {
        guard let reciter, !plan.isEmpty else { return }
        stop()
        generation += 1
        self.plan = plan
        sequence = plan.sequence
        index = 0
        enqueued = 0
        currentKey = sequence.first
        wantsPlaying = true
        status = .loading
        activateSession()
        setUpRemoteCommands()
        updateNowPlaying()
        startLoading(reciter: reciter, generation: generation)
    }

    /// Plays the plan, or pauses and resumes it when it is already the active one.
    func toggle(_ plan: PlaybackPlan) {
        if self.plan == plan, status != .idle, status != .failed {
            togglePause()
        } else {
            play(plan)
        }
    }

    func togglePause() {
        switch status {
        case .playing, .loading: pause()
        case .paused: resume()
        case .idle, .failed: break
        }
    }

    func pause() {
        guard status == .playing || status == .loading else { return }
        wantsPlaying = false
        player.pause()
        status = .paused
        updateNowPlaying()
    }

    func resume() {
        guard status == .paused else { return }
        wantsPlaying = true
        activateSession()
        if index < enqueued {
            player.play()
            status = .playing
        } else {
            status = .loading
        }
        updateNowPlaying()
    }

    func stop() {
        generation += 1
        loader?.cancel()
        loader = nil
        wantsPlaying = false
        player.pause()
        player.removeAllItems()
        positions = [:]
        sequence = []
        plan = nil
        currentKey = nil
        index = 0
        enqueued = 0
        status = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// True while this plan is the one loaded (playing, loading or paused).
    func isActive(_ plan: PlaybackPlan) -> Bool {
        self.plan == plan && status != .idle && status != .failed
    }

    // MARK: Loading

    private func startLoading(reciter: Reciter, generation: Int) {
        let keys = sequence
        loader = Task { [weak self] in
            for (position, key) in keys.enumerated() {
                // Stay a few recordings ahead of the one playing, no more.
                while let self, self.generation == generation, position - self.index >= Self.lookahead {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                do {
                    let file = try await self.cache.file(reciter: reciter, key: key)
                    guard self.generation == generation, !Task.isCancelled else { return }
                    self.enqueue(file: file, position: position)
                } catch {
                    guard self.generation == generation else { return }
                    self.loadFailed(at: position)
                    return
                }
            }
        }
    }

    private func enqueue(file: URL, position: Int) {
        let item = AVPlayerItem(url: file)
        positions[ObjectIdentifier(item)] = position
        player.insert(item, after: nil)
        enqueued = position + 1
        if wantsPlaying {
            player.play()
            if status == .loading, position >= index { status = .playing }
            updateNowPlaying()
        }
    }

    /// A recording could not be fetched. What is already queued plays out; if nothing is, playback stops.
    private func loadFailed(at position: Int) {
        sequence = Array(sequence.prefix(position))
        if position <= index {
            stop()
            status = .failed
        }
    }

    // MARK: Following along

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            let seconds = item.duration.seconds
            MainActor.assumeIsolated { self?.finished(id: id, seconds: seconds) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began {
                    self.pause()
                } else if type == .ended, options?.contains(.shouldResume) == true {
                    self.resume()
                }
            }
        })
    }

    private func finished(id: ObjectIdentifier, seconds: Double) {
        guard let position = positions.removeValue(forKey: id) else { return }
        if seconds.isFinite, seconds > 0 { onListened?(seconds) }
        let next = position + 1
        guard next < sequence.count else {
            stop()
            return
        }
        index = next
        currentKey = sequence[next]
        if next >= enqueued, wantsPlaying { status = .loading }
        updateNowPlaying()
    }

    // MARK: System integration

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func updateNowPlaying() {
        guard let currentKey else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: titleFor(currentKey),
            MPNowPlayingInfoPropertyPlaybackRate: status == .playing ? 1.0 : 0.0,
        ]
        if let reciter { info[MPMediaItemPropertyArtist] = reciter.name }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setUpRemoteCommands() {
        guard !remoteCommandsReady else { return }
        remoteCommandsReady = true
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePause() }
            return .success
        }
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
    }
}

/// A round play or pause button for one playback plan. Shows a spinner while the recording loads.
struct PlayButton: View {
    @Environment(RecitationPlayer.self) private var player
    let plan: PlaybackPlan
    let label: String
    var diameter: CGFloat = 44
    var filled = false

    var body: some View {
        let active = player.isActive(plan)
        Button {
            player.toggle(plan)
        } label: {
            ZStack {
                if active, player.status == .loading {
                    ProgressView()
                        .tint(filled ? Palette.onAccent : Palette.accent)
                } else {
                    Image(systemName: active && player.status == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: diameter * 0.34, weight: .semibold))
                }
            }
            .foregroundStyle(filled ? Palette.onAccent : Palette.accent)
            .frame(width: diameter, height: diameter)
            .background(filled ? Palette.accent : .clear, in: Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active && player.isPlaying ? String(localized: "Pause") : label)
    }
}
