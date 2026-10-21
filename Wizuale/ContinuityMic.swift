import AVFoundation
import Foundation
import QuartzCore

/// Uses an iPhone or iPad as the Apple TV's Continuity Microphone.
/// Voice processing stays off: echo cancellation would strip the music.
/// The session is activated only after a Continuity input is actually connected,
/// and it mixes with whatever is already playing.
final class ContinuityMic: NSObject {
    var onFeatures: ((MicFeatures) -> Void)?
    var onStatus: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var analyzer = BandAnalyzer()
    private var tapInstalled = false
    private var wanted = false
    private var allowed = false
    private var sessionLive = false
    private var observing = false
    private var routeObserver: NSObjectProtocol?

    func start() {
        if wanted { return }
        wanted = true
        lock.lock()
        analyzer = BandAnalyzer()
        lock.unlock()
        observe()
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.wanted else { return }
                self.allowed = granted
                if granted {
                    self.refreshRoute()
                } else {
                    self.onStatus?("Microphone access is off. Enable Wizuale in Settings → Privacy → Microphone.")
                }
            }
        }
    }

    func stop() {
        wanted = false
        allowed = false
        tearDownEngine()
        if sessionLive {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            sessionLive = false
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        if observing {
            AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "isInputAvailable")
        }
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        let session = AVAudioSession.sharedInstance()
        session.addObserver(self, forKeyPath: "isInputAvailable", options: [.new], context: nil)
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRoute()
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "isInputAvailable" else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refreshRoute()
        }
    }

    private func refreshRoute() {
        guard wanted, allowed else { return }
        let session = AVAudioSession.sharedInstance()
        let port = session.currentRoute.inputs.first { $0.portType == .continuityMicrophone }
        if let port {
            beginEngine(preferred: port)
        } else {
            tearDownEngine()
            if sessionLive {
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                sessionLive = false
            }
            onStatus?("Pair an iPhone or iPad. Continuity is not connected yet.")
        }
    }

    private func beginEngine(preferred: AVAudioSession.PortDescription) {
        if tapInstalled { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try configure(session)
            try? session.setPreferredInput(preferred)
            try? session.setPreferredSampleRate(48_000)
            try? session.setPreferredIOBufferDuration(1.0 / 60.0)
            try session.setActive(true)
            sessionLive = true
        } catch {
            onStatus?("The Continuity microphone did not start. \(error.localizedDescription)")
            return
        }

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(false)
        input.isVoiceProcessingBypassed = true
        input.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            engine.stop()
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            sessionLive = false
            onStatus?("The Continuity microphone did not start. \(error.localizedDescription)")
            return
        }
        if input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(false)
        }
        input.isVoiceProcessingBypassed = true
        onStatus?("Continuity microphone is live.")
    }

    /// Measurement mode keeps the system's voice processing off. mixWithOthers
    /// leaves Apple Music playing. Never use a voice-chat mode here.
    private func configure(_ session: AVAudioSession) throws {
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        } catch {
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            } catch {
                try session.setCategory(.record, mode: .measurement, options: [.mixWithOthers])
            }
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 1, buffer.frameLength > 0 else { return }
        let samples = MicPCM.monoFloats(from: buffer)
        guard !samples.isEmpty else { return }
        lock.lock()
        let features = analyzer.consume(samples, sampleRate: rate)
        lock.unlock()
        onFeatures?(features)
    }

    private func tearDownEngine() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
    }
}
