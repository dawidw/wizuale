import AVFoundation
import Combine
import Foundation
import Network
import os
import QuartzCore
import UIKit

/// Microphone, analysis, and the UDP link to whichever Apple TV is advertising.
/// `linked` is true only after the TV has answered, not when the socket opens.
/// The screen stays awake for as long as this is running.
final class MicCapture: ObservableObject {
    private let log = Logger(subsystem: "app.wizuale", category: "MicPhone")

    @Published private(set) var running = false
    @Published private(set) var linked = false
    @Published private(set) var status = "Tap Start. Allow the microphone and local network when asked."
    @Published private(set) var tvName = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var bassLevel: Float = 0
    @Published private(set) var activePreset = 0
    @Published private(set) var cycling = true
    @Published private(set) var pictureKnown = false
    @Published private(set) var calibrating = false
    @Published private(set) var calibrateProgress: Double = 0
    @Published private(set) var calibrateMessage = ""
    @Published private(set) var dropActive = false
    @Published var sensitivity: Float = MicTuning.loadSensitivity() {
        didSet {
            let clamped = MicTuning.clampSensitivity(sensitivity)
            if clamped != sensitivity {
                sensitivity = clamped
                return
            }
            flag.lock()
            heldSensitivity = clamped
            flag.unlock()
            guard !applyingRemote, clamped != oldValue else { return }
            MicTuning.saveSensitivity(clamped)
            scheduleSettings()
        }
    }
    @Published var latencyMs: Int = MicTuning.loadLatency() {
        didSet {
            let clamped = MicTuning.clampLatency(latencyMs)
            if clamped != latencyMs {
                latencyMs = clamped
                return
            }
            guard !applyingRemote, clamped != oldValue else { return }
            MicTuning.saveLatency(clamped)
            scheduleSettings()
        }
    }
    @Published var autoCycle: Bool = MicTuning.loadAutoCycle() {
        didSet {
            guard !applyingRemote, autoCycle != oldValue else { return }
            MicTuning.saveAutoCycle(autoCycle)
            scheduleCycle()
        }
    }
    @Published var tvAudioDebug = false {
        didSet {
            guard !applyingRemote, tvAudioDebug != oldValue else { return }
            scheduleTVAudioDebug()
        }
    }
    @Published var cycleSeconds: Int = MicTuning.loadCycleSeconds() {
        didSet {
            let clamped = MicTuning.clampCycleSeconds(cycleSeconds)
            if clamped != cycleSeconds {
                cycleSeconds = clamped
                return
            }
            guard !applyingRemote, clamped != oldValue else { return }
            MicTuning.saveCycleSeconds(clamped)
            scheduleCycle()
        }
    }

    private let engine = AVAudioEngine()
    private let network = DispatchQueue(label: "app.wizuale.mic.send")
    private let flag = NSLock()
    private let calibrateFlag = NSLock()
    private var analyzer = BandAnalyzer()
    private var tapInstalled = false
    private var sequence: UInt16 = 0
    private var commandSequence: UInt16 = 0
    private var settingsSequence: UInt16 = 0
    private var boostSequence: UInt16 = 0
    private var pcmSequence: UInt16 = 0
    private var cycleSequence: UInt16 = 0
    private var debugSequence: UInt16 = 0
    private var pendingPCM: [Data] = []
    private var heldSensitivity: Float = MicTuning.loadSensitivity()
    private var applyingRemote = false
    private var lastUI: CFTimeInterval = 0
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var connectedName = ""
    private var pendingAudio: Data?
    private var pendingCommands: [Data] = []
    private var pendingSettings: Data?
    private var pendingBoost: Data?
    private var pendingDebug: Data?
    private var lastCommand: Data?
    private var lastSettings: Data?
    private var lastBoost: Data?
    private var sending = false
    private var pcmInFlight = 0
    private let maxPCMInFlight = 24
    private let pcmRingLock = NSLock()
    private var pcmRing: [Int16] = []
    private var pcmWireRate: Float = 48_000
    private var pcmSendTimer: DispatchSourceTimer?
    /// 10 ms @ 48 kHz — one steady datagram per timer tick.
    private let pcmFramesPerPacket = 480
    private var receiving = false
    private var wantsLink = false
    private var epoch = 0
    private var confirmed = false
    private var lastAck: CFTimeInterval = 0
    private var sendToken = 0
    /// After a tap, ignore acks that still name the pre-tap picture for this long.
    private var tapIgnoreUntil: CFTimeInterval = 0
    private var tapStalePreset = 0
    private var tapStaleCycling = true
    private var sensHold: Float = 1
    private var latHold = 0
    private var sensHoldUntil: CFTimeInterval = 0
    private var latHoldUntil: CFTimeInterval = 0
    private var startGeneration = 0
    private var interruption: NSObjectProtocol?
    private var calibrateOn = false
    private var calibrateBegan: CFTimeInterval = 0
    private var calibrateSums = MicNoiseFloor.zero
    private var calibrateCount = 0
    private var dropHeld = false
    private var pressBegan: Date?
    private var releaseWork: DispatchWorkItem?
    private var pulseToken = 0

    init() {
        analyzer.apply(floor: MicCalibrationStore.load())
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.interrupted(notification)
        }
    }

    deinit {
        if let interruption {
            NotificationCenter.default.removeObserver(interruption)
        }
    }

    func toggle() {
        if running {
            stop()
        } else {
            start()
        }
    }

    func start() {
        startGeneration += 1
        let generation = startGeneration
        status = "Asking for the microphone…"
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.startGeneration == generation else { return }
                if granted {
                    self.beginEngine()
                } else {
                    self.running = false
                    self.cancelCalibration()
                    self.status = "Microphone access is off. Enable Wizuale Mic in Settings → Privacy → Microphone."
                }
            }
        }
    }

    /// `PresetWire.auto` restores auto cycling. Any other value asks the TV to
    /// lock that index. The strip updates immediately; the TV ack keeps it honest.
    func selectPreset(_ choice: Int) {
        let wire: Int16
        if choice < 0 {
            wire = PresetWire.auto
        } else {
            guard MilkPresetCatalog.presets.indices.contains(choice) else { return }
            wire = Int16(clamping: choice)
        }
        let stalePreset = activePreset
        let staleCycling = cycling
        applyPictureHighlight(choice: choice)
        flag.lock()
        commandSequence &+= 1
        if commandSequence == 0 { commandSequence = 1 }
        let seq = commandSequence
        flag.unlock()
        let packet = MicWire.encodeCommand(sequence: seq, preset: wire)
        network.async { [weak self] in
            guard let self else { return }
            self.tapIgnoreUntil = CACurrentMediaTime() + 0.4
            self.tapStalePreset = stalePreset
            self.tapStaleCycling = staleCycling
            self.enqueueCommand(packet)
        }
    }

    /// Records about five seconds of room noise and saves a floor for each band.
    /// Ask the listener to keep the room quiet while the progress bar moves.
    func calibrate() {
        guard !calibrating else { return }
        calibrateFlag.lock()
        calibrateOn = true
        calibrateBegan = 0
        calibrateSums = .zero
        calibrateCount = 0
        calibrateFlag.unlock()
        calibrating = true
        calibrateProgress = 0
        calibrateMessage = "Keep the room quiet."
        if !running {
            start()
        }
    }

    /// Press holds the Drop. A short tap keeps it going for about three seconds.
    /// The TV plays the zoom once, then eases the warp and flash back.
    func setDrop(pressed: Bool) {
        if pressed {
            releaseWork?.cancel()
            releaseWork = nil
            guard !dropHeld else { return }
            dropHeld = true
            pressBegan = Date()
            dropActive = true
            beginBoost(1)
        } else if dropHeld {
            dropHeld = false
            let duration = Date().timeIntervalSince(pressBegan ?? Date())
            if duration < 0.45 {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !self.dropHeld else { return }
                    self.dropActive = false
                    self.beginBoost(0)
                }
                releaseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            } else {
                dropActive = false
                beginBoost(0)
            }
        }
    }

    func stop() {
        startGeneration += 1
        cancelCalibration()
        tearDown(status: "Tap Start. Allow the microphone and local network when asked.")
    }

    private func beginEngine() {
        bumpEpoch()
        let session = AVAudioSession.sharedInstance()
        var measuring = true
        do {
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            } catch {
                measuring = false
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            }
            try? session.setPreferredSampleRate(48_000)
            try? session.setPreferredIOBufferDuration(1.0 / 60.0)
            if session.isInputGainSettable {
                try? session.setInputGain(1)
            }
            try session.setActive(true)
        } catch {
            status = "The audio session did not start. \(error.localizedDescription)"
            cancelCalibration()
            return
        }

        analyzer = BandAnalyzer()
        analyzer.apply(floor: MicCalibrationStore.load())
        sequence = 0
        lastUI = 0
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        network.async { [weak self] in
            self?.startPCMSender()
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            status = "The microphone did not start. \(error.localizedDescription)"
            cancelCalibration()
            return
        }

        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        if measuring {
            status = "Listening. Allow Local Network if an Apple TV never appears."
        } else {
            status = "Listening. System gain is on, so quiet rooms may be squashed."
        }
        setWantsLink(true)
        let sens = sensitivity
        let latency = latencyMs
        network.async { [weak self] in
            guard let self else { return }
            if self.lastSettings == nil {
                self.settingsSequence = 1
                self.lastSettings = MicWire.encodeSettings(
                    sequence: 1, latencyMs: latency, sensitivity: sens
                )
            }
            self.scheduleCycleOnNetwork()
            self.startBrowser()
        }
    }

    private func tearDown(status next: String) {
        bumpEpoch()
        setWantsLink(false)
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        network.async { [weak self] in
            self?.stopPCMSender()
            self?.stopLink()
        }
        running = false
        linked = false
        tvName = ""
        level = 0
        bassLevel = 0
        status = next
        UIApplication.shared.isIdleTimerDisabled = false
        network.async { [weak self] in
            self?.confirmed = false
            self?.lastAck = 0
        }
    }

    private func interrupted(_ notification: Notification) {
        guard running else { return }
        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        cancelCalibration()
        tearDown(status: "Audio was interrupted. Tap Start to listen again.")
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 1, buffer.frameLength > 0 else { return }
        let samples = MicPCM.monoFloats(from: buffer)
        guard !samples.isEmpty else { return }
        let features = analyzer.consume(samples, sampleRate: rate)
        let raw = analyzer.lastRaw
        noteCalibration(raw)
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        let packet = MicWire.encodeAudio(
            sequence: sequence,
            features: features,
            sensitivity: currentSensitivity()
        )
        let pcmPacked = MicPCM.monoInt16(from: buffer, maxFrames: Int.max)
        pcmRingLock.lock()
        pcmWireRate = Float(pcmPacked.sampleRate)
        pcmRing.append(contentsOf: pcmPacked.samples)
        let cap = max(Int(pcmWireRate * 1.25), pcmFramesPerPacket * 8)
        if pcmRing.count > cap {
            pcmRing.removeFirst(pcmRing.count - cap)
        }
        pcmRingLock.unlock()
        let loud = features.loudness
        let bass = features.bass
        let now = CACurrentMediaTime()
        let publishUI = now - lastUI >= (1.0 / 15.0)
        if publishUI { lastUI = now }
        network.async { [weak self] in
            self?.enqueueAudio(packet)
            if publishUI { self?.refreshLink() }
        }
        if publishUI {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.level = loud
                self.bassLevel = bass
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }

    private func noteCalibration(_ raw: MicBandEnergy) {
        calibrateFlag.lock()
        let on = calibrateOn
        if on {
            if calibrateBegan == 0 { calibrateBegan = CACurrentMediaTime() }
            calibrateSums.bass += raw.bass
            calibrateSums.lowMid += raw.lowMid
            calibrateSums.mid += raw.mid
            calibrateSums.high += raw.high
            calibrateSums.loudness += raw.loudness
            calibrateCount += 1
        }
        let began = calibrateBegan
        let count = calibrateCount
        let sums = calibrateSums
        calibrateFlag.unlock()
        guard on else { return }
        let elapsed = CACurrentMediaTime() - began
        if elapsed >= 5, count > 10 {
            calibrateFlag.lock()
            let still = calibrateOn
            calibrateOn = false
            calibrateFlag.unlock()
            guard still else { return }
            let scale = 1.2 / Float(count)
            let floor = MicNoiseFloor(
                bass: sums.bass * scale,
                lowMid: sums.lowMid * scale,
                mid: sums.mid * scale,
                high: sums.high * scale,
                loudness: sums.loudness * scale
            )
            analyzer.apply(floor: floor)
            MicCalibrationStore.save(floor)
            calibrateFlag.lock()
            calibrateOn = false
            calibrateFlag.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.calibrating = false
                self.calibrateProgress = 1
                self.calibrateMessage = "Calibration saved. Bass, mids, highs, and level sit above the room."
            }
        } else {
            let progress = min(max(elapsed / 5, 0), 1)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.calibrating else { return }
                self.calibrateProgress = progress
                self.calibrateMessage = "Keep the room quiet."
            }
        }
    }

    private func cancelCalibration() {
        calibrateFlag.lock()
        let was = calibrateOn
        calibrateOn = false
        calibrateFlag.unlock()
        guard was else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.calibrating = false
            self.calibrateProgress = 0
            self.calibrateMessage = ""
        }
    }

    private func setWantsLink(_ value: Bool) {
        flag.lock()
        wantsLink = value
        flag.unlock()
    }

    private func linkWanted() -> Bool {
        flag.lock()
        defer { flag.unlock() }
        return wantsLink
    }

    private func currentSensitivity() -> Float {
        flag.lock()
        defer { flag.unlock() }
        return heldSensitivity
    }

    private func bumpEpoch() {
        flag.lock()
        epoch += 1
        flag.unlock()
    }

    private func epochNow() -> Int {
        flag.lock()
        defer { flag.unlock() }
        return epoch
    }

    private func scheduleSettings() {
        let sens = sensitivity
        let latency = latencyMs
        flag.lock()
        settingsSequence &+= 1
        if settingsSequence == 0 { settingsSequence = 1 }
        let seq = settingsSequence
        flag.unlock()
        let packet = MicWire.encodeSettings(sequence: seq, latencyMs: latency, sensitivity: sens)
        network.async { [weak self] in
            guard let self else { return }
            self.sensHold = sens
            self.latHold = latency
            self.sensHoldUntil = CACurrentMediaTime() + 0.45
            self.latHoldUntil = self.sensHoldUntil
            self.pendingSettings = packet
            self.lastSettings = packet
            self.pump()
        }
    }

    private func scheduleCycle() {
        network.async { [weak self] in
            self?.scheduleCycleOnNetwork()
        }
    }

    private func scheduleCycleOnNetwork() {
        let auto = autoCycle
        let seconds = cycleSeconds
        flag.lock()
        cycleSequence &+= 1
        if cycleSequence == 0 { cycleSequence = 1 }
        let seq = cycleSequence
        flag.unlock()
        let packet = MicWire.encodeCycle(sequence: seq, autoAdvance: auto, intervalSeconds: seconds)
        pendingCommands.append(packet)
        if pendingCommands.count > 8 {
            pendingCommands.removeFirst(pendingCommands.count - 8)
        }
        pump()
    }

    private func beginBoost(_ amount: Float) {
        pulseToken += 1
        let token = pulseToken
        emitBoost(amount)
        guard amount > 0.5 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.pulseToken == token else { return }
                self.emitBoost(0)
            }
            return
        }
        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.pulseToken == token, self.dropActive else { return }
                self.emitBoost(1)
                tick()
            }
        }
        tick()
    }

    private func emitBoost(_ amount: Float) {
        flag.lock()
        boostSequence &+= 1
        if boostSequence == 0 { boostSequence = 1 }
        let seq = boostSequence
        flag.unlock()
        let packet = MicWire.encodeBoost(sequence: seq, amount: amount)
        network.async { [weak self] in
            guard let self else { return }
            self.pendingBoost = packet
            self.lastBoost = packet
            self.pump()
        }
    }

    private func startBrowser() {
        guard linkWanted() else { return }
        browser?.cancel()
        let params = NWParameters.udp
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVoice
        let created = NWBrowser(
            for: NWBrowser.Descriptor.bonjour(type: MicWire.serviceType, domain: nil),
            using: params
        )
        created.stateUpdateHandler = { [weak self] state in
            self?.browserState(state)
        }
        created.browseResultsChangedHandler = { [weak self] results, _ in
            self?.adopt(results)
        }
        created.start(queue: network)
        browser = created
    }

    private func browserState(_ state: NWBrowser.State) {
        guard linkWanted() else { return }
        switch state {
        case .failed(let error):
            publish(status: "Local network failed. \(error.localizedDescription)", linked: false)
            confirmed = false
            network.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startBrowser()
            }
        case .waiting(let error):
            publish(status: "Waiting for local network. Allow Wizuale Mic under Settings → Privacy → Local Network. \(error.localizedDescription)")
        default:
            break
        }
    }

    private func adopt(_ results: Set<NWBrowser.Result>) {
        guard linkWanted() else { return }
        var found: [(String, NWEndpoint)] = []
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                found.append((name, result.endpoint))
            }
        }
        found.sort { $0.0 < $1.0 }
        // An empty callback in the middle of browsing is common. Dropping the
        // socket there makes the picture hiccup, so only switch when a real list arrives.
        guard let first = found.first else {
            if connection == nil {
                publish(status: "Allow Local Network if an Apple TV never appears.", tv: "", linked: false)
            }
            return
        }
        if connection != nil, found.contains(where: { $0.0 == connectedName }) {
            return
        }
        connect(endpoint: first.1, name: first.0)
    }

    private func connect(endpoint: NWEndpoint, name: String) {
        dropConnection()
        let params = NWParameters.udp
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVoice
        let created = NWConnection(to: endpoint, using: params)
        connectedName = name
        connection = created
        created.stateUpdateHandler = { [weak self] state in
            self?.connectionState(state, name: name)
        }
        created.start(queue: network)
        publish(status: "Found \(name). Waiting for the Wizuale app.", tv: name, linked: false)
    }

    private func connectionState(_ state: NWConnection.State, name: String) {
        guard linkWanted(), connectedName == name else { return }
        switch state {
        case .ready:
            if !confirmed {
                publish(status: "Found \(name). Waiting for the Wizuale app.", tv: name, linked: false)
            }
            if !receiving {
                receiving = true
                receiveAck()
            }
            if pendingCommands.isEmpty, let lastCommand {
                pendingCommands.append(lastCommand)
            }
            if pendingSettings == nil, let lastSettings {
                pendingSettings = lastSettings
            }
            if let lastBoost {
                pendingBoost = lastBoost
            }
            startPCMSender()
            pump()
        case .failed(let error):
            confirmed = false
            publish(status: "Could not reach \(name). \(error.localizedDescription)", tv: name, linked: false)
            dropConnection()
        case .waiting(let error):
            confirmed = false
            publish(status: "Waiting for \(name). \(error.localizedDescription)", tv: name, linked: false)
        case .cancelled:
            break
        case .preparing:
            publish(status: "Found \(name). Waiting for the Wizuale app.", tv: name, linked: false)
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func receiveAck() {
        guard let connection, receiving else { return }
        connection.receiveMessage { [weak self] data, _, _, error in
            self?.network.async {
                guard let self, self.receiving else { return }
                if let data {
                    if let packet = MicWire.decode(data) {
                        if case .ack(let preset, let cycling, let latency, let sensitivity) = packet {
                            self.log.debug("ack received preset=\(preset) cycling=\(cycling)")
                            self.noteAck(preset: preset, cycling: cycling)
                            self.noteRemoteTuning(latency: latency, sensitivity: sensitivity)
                        }
                    } else if data.count >= 6, MicWire.peekKind(data) == MicWire.kindAck {
                        self.log.error("ack decode failed (\(data.count) bytes)")
                    }
                }
                if error != nil {
                    self.confirmed = false
                    let name = self.connectedName
                    self.publish(
                        status: name.isEmpty ? "Searching for Apple TV…" : "Lost \(name). Looking again.",
                        linked: false
                    )
                    self.dropConnection()
                    return
                }
                self.receiveAck()
            }
        }
    }

    private func noteAck(preset: Int16, cycling ackCycling: Bool) {
        guard linkWanted() else { return }
        lastAck = CACurrentMediaTime()
        confirmed = true
        let name = connectedName.isEmpty ? "Apple TV" : connectedName
        let index = Int(preset)
        guard MilkPresetCatalog.presets.indices.contains(index) else {
            log.error("ack ignored invalid preset index \(index)")
            return
        }
        let now = CACurrentMediaTime()
        if now < tapIgnoreUntil,
           index == tapStalePreset,
           ackCycling == tapStaleCycling {
            log.debug("ack ignored stale preset=\(index) cycling=\(ackCycling)")
            publish(status: "The picture is following this phone.", tv: name, linked: true)
            return
        }
        log.debug("highlight applied preset=\(index) cycling=\(ackCycling)")
        let picture = MilkPresetCatalog.preset(at: index)?.displayName ?? "Preset"
        let detail = ackCycling ? "Auto is on. Showing \(picture)." : "Locked on \(picture)."
        applyPictureHighlight(preset: index, cycling: ackCycling, known: true)
        publish(status: detail, tv: name, linked: true)
    }

    private func noteRemoteTuning(latency: Int?, sensitivity: Float?) {
        let now = CACurrentMediaTime()
        let nextSens: Float? = {
            guard let sensitivity else { return nil }
            if now < sensHoldUntil && abs(sensitivity - sensHold) >= 0.03 { return nil }
            return sensitivity
        }()
        let nextLat: Int? = {
            guard let latency else { return nil }
            if now < latHoldUntil && latency != latHold { return nil }
            return latency
        }()
        guard nextSens != nil || nextLat != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyingRemote = true
            if let nextSens {
                self.sensitivity = nextSens
            }
            if let nextLat {
                self.latencyMs = nextLat
            }
            self.applyingRemote = false
        }
    }

    private func refreshLink() {
        guard confirmed else { return }
        if CACurrentMediaTime() - lastAck > 1.1 {
            confirmed = false
            publish(status: "Searching for Apple TV…", linked: false)
        }
    }

    private func enqueueAudio(_ data: Data) {
        guard linkWanted() else { return }
        pendingAudio = data
        pump()
    }

    private func enqueuePCM(_ data: Data) {
        guard linkWanted() else { return }
        pendingPCM.append(data)
        if pendingPCM.count > 160 {
            pendingPCM.removeFirst(pendingPCM.count - 160)
        }
        pump()
    }

    private func startPCMSender() {
        pcmSendTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: network)
        timer.schedule(deadline: .now() + .milliseconds(4), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.tickPCMSend()
        }
        timer.resume()
        pcmSendTimer = timer
    }

    private func stopPCMSender() {
        pcmSendTimer?.cancel()
        pcmSendTimer = nil
        pcmRingLock.lock()
        pcmRing.removeAll(keepingCapacity: true)
        pcmRingLock.unlock()
        pendingPCM.removeAll()
        pcmInFlight = 0
    }

    private func tickPCMSend() {
        guard linkWanted(), let connection, connection.state == .ready else { return }
        pcmRingLock.lock()
        let rate = pcmWireRate
        let want = pcmFramesPerPacket
        let take = min(want, pcmRing.count)
        let block = take > 0 ? Array(pcmRing.prefix(take)) : []
        if take > 0 {
            pcmRing.removeFirst(take)
        }
        pcmRingLock.unlock()
        guard block.count >= want / 2, rate > 1000 else { return }
        pcmSequence &+= 1
        if pcmSequence == 0 { pcmSequence = 1 }
        let packet = MicWire.encodePCM(
            sequence: pcmSequence,
            sampleRate: rate,
            samples: block
        )
        enqueuePCM(packet)
    }

    private func enqueueCommand(_ data: Data) {
        lastCommand = data
        pendingCommands.append(data)
        if pendingCommands.count > 6 {
            pendingCommands.removeFirst(pendingCommands.count - 6)
        }
        pump()
    }

    private func scheduleTVAudioDebug() {
        debugSequence &+= 1
        if debugSequence == 0 { debugSequence = 1 }
        let packet = MicWire.encodeDebug(sequence: debugSequence, showAudioOverlay: tvAudioDebug)
        network.async { [weak self] in
            self?.pendingDebug = packet
            self?.pump()
        }
    }

    private func pump() {
        guard let connection, connection.state == .ready else { return }
        while pcmInFlight < maxPCMInFlight, !pendingPCM.isEmpty {
            startSend(pendingPCM.removeFirst(), isPCM: true, on: connection)
        }
        guard !sending, pendingPCM.isEmpty else { return }
        let data: Data?
        if !pendingCommands.isEmpty {
            data = pendingCommands.removeFirst()
        } else if let debug = pendingDebug {
            pendingDebug = nil
            data = debug
        } else if let boost = pendingBoost {
            pendingBoost = nil
            data = boost
        } else if let settings = pendingSettings {
            pendingSettings = nil
            data = settings
        } else if let audio = pendingAudio {
            pendingAudio = nil
            data = audio
        } else if !pendingPCM.isEmpty {
            data = pendingPCM.removeFirst()
        } else {
            return
        }
        startSend(data!, isPCM: false, on: connection)
    }

    private func startSend(_ data: Data, isPCM: Bool, on connection: NWConnection) {
        if isPCM {
            pcmInFlight += 1
        } else {
            sending = true
        }
        let token = sendToken
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.network.async {
                guard let self, self.sendToken == token else { return }
                if isPCM {
                    self.pcmInFlight = max(0, self.pcmInFlight - 1)
                } else {
                    self.sending = false
                }
                self.pump()
            }
        })
    }

    private func stopLink() {
        browser?.cancel()
        browser = nil
        dropConnection()
    }

    private func dropConnection() {
        stopPCMSender()
        sendToken += 1
        connection?.cancel()
        connection = nil
        connectedName = ""
        pendingAudio = nil
        pendingPCM.removeAll()
        pendingCommands.removeAll()
        sending = false
        receiving = false
        confirmed = false
        lastAck = 0
        tapIgnoreUntil = 0
    }

    /// Optimistic strip highlight from a tap (`choice` is `-1` or `PresetWire.auto` for Auto).
    private func applyPictureHighlight(choice: Int) {
        if choice < 0 || choice == Int(PresetWire.auto) {
            applyPictureHighlight(preset: activePreset, cycling: true, known: true)
        } else if MilkPresetCatalog.presets.indices.contains(choice) {
            applyPictureHighlight(preset: choice, cycling: false, known: true)
        }
    }

    private func applyPictureHighlight(preset: Int, cycling: Bool, known: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            if MilkPresetCatalog.presets.indices.contains(preset) {
                self.activePreset = preset
            }
            self.cycling = cycling
            self.pictureKnown = known
        }
    }

    private func publish(
        status: String? = nil,
        tv: String? = nil,
        linked: Bool? = nil
    ) {
        let epoch = epochNow()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.epochNow() == epoch else { return }
            if let status { self.status = status }
            if let tv { self.tvName = tv }
            if let linked { self.linked = linked }
        }
    }
}
