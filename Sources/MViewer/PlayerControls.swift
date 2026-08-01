import AppKit
import AVFoundation

/// Floating playback controls for the 360° view, where AVPlayerView (and its
/// built-in controls) is not available: play/pause, scrubbing timeline with
/// time labels, and volume/mute.
final class PlayerControlsBar: NSVisualEffectView {
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?
    private var lastScrub = Date.distantPast

    private let playButton = NSButton()
    private let currentLabel = NSTextField(labelWithString: "0:00")
    private let timeSlider = NSSlider()
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let muteButton = NSButton()
    private let volumeSlider = NSSlider()

    static let barSize = NSSize(width: 560, height: 46)

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.barSize))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        playButton.isBordered = false
        playButton.bezelStyle = .regularSquare
        playButton.imageScaling = .scaleProportionallyUpOrDown
        playButton.frame = NSRect(x: 10, y: 11, width: 24, height: 24)
        playButton.target = self
        playButton.action = #selector(togglePlay)
        addSubview(playButton)

        for label in [currentLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
        }
        currentLabel.frame = NSRect(x: 40, y: 15, width: 54, height: 16)
        addSubview(currentLabel)

        timeSlider.frame = NSRect(x: 100, y: 13, width: 276, height: 20)
        timeSlider.minValue = 0
        timeSlider.target = self
        timeSlider.action = #selector(scrub)
        addSubview(timeSlider)

        durationLabel.frame = NSRect(x: 382, y: 15, width: 54, height: 16)
        addSubview(durationLabel)

        muteButton.isBordered = false
        muteButton.bezelStyle = .regularSquare
        muteButton.imageScaling = .scaleProportionallyUpOrDown
        muteButton.frame = NSRect(x: 442, y: 13, width: 22, height: 20)
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        addSubview(muteButton)

        volumeSlider.frame = NSRect(x: 470, y: 13, width: 80, height: 20)
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.target = self
        volumeSlider.action = #selector(changeVolume)
        addSubview(volumeSlider)
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(_ player: AVPlayer) {
        detach()
        self.player = player
        volumeSlider.doubleValue = Double(player.volume)
        updatePlayIcon()
        updateMuteIcon()
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updatePlayIcon() }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main
        ) { [weak self] time in
            self?.tick(time)
        }
    }

    func detach() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        rateObservation?.invalidate()
        rateObservation = nil
        player = nil
    }

    private func tick(_ time: CMTime) {
        guard let item = player?.currentItem else { return }
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 {
            timeSlider.maxValue = duration
            durationLabel.stringValue = Self.format(duration)
        }
        currentLabel.stringValue = Self.format(time.seconds)
        // Don't fight the user while they are scrubbing.
        if Date().timeIntervalSince(lastScrub) > 0.5 {
            timeSlider.doubleValue = time.seconds
        }
    }

    private func updatePlayIcon() {
        let name = (player?.rate ?? 0) == 0 ? "play.fill" : "pause.fill"
        playButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Play/Pause")
    }

    private func updateMuteIcon() {
        let name = (player?.isMuted ?? false) ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Mute")
    }

    @objc private func togglePlay() {
        guard let player else { return }
        player.rate == 0 ? player.play() : player.pause()
    }

    @objc private func scrub() {
        lastScrub = Date()
        let time = CMTime(seconds: timeSlider.doubleValue, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @objc private func changeVolume() {
        guard let player else { return }
        player.volume = Float(volumeSlider.doubleValue)
        if player.isMuted, volumeSlider.doubleValue > 0 {
            player.isMuted = false
        }
        updateMuteIcon()
    }

    @objc private func toggleMute() {
        guard let player else { return }
        player.isMuted.toggle()
        updateMuteIcon()
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
