import AVFoundation
import Combine
import Darwin
import Foundation
import Network
import QuartzCore
import UIKit

/// Biquad in direct form I. Coefficients are the RBJ cookbook, already divided by a0.
private struct Biquad {
    var b0: Float = 0
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        if abs(y) < 1e-20 { return 0 }
        return y
    }

    static func lowpass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        coefficients(kind: 0, cutoff: cutoff, sampleRate: sampleRate, q: q)
    }

    static func bandpass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        coefficients(kind: 1, cutoff: cutoff, sampleRate: sampleRate, q: q)
    }

    static func highpass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        coefficients(kind: 2, cutoff: cutoff, sampleRate: sampleRate, q: q)
    }

    /// kind 0 lowpass, 1 constant-peak bandpass, 2 highpass.
    private static func coefficients(kind: Int, cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        let rate = max(sampleRate, 8_000)
        let fc = min(max(cutoff, 20), rate * 0.45)
        let resonance = max(q, 0.2)
        let w0 = 2 * Double.pi * fc / rate
        let cosine = Darwin.cos(w0)
        let sine = Darwin.sin(w0)
        let alpha = sine / (2 * resonance)
        let b0: Double
        let b1: Double
        let b2: Double
        if kind == 1 {
            b0 = alpha
            b1 = 0
            b2 = -alpha
        } else if kind == 2 {
            b0 = (1 + cosine) / 2
            b1 = -(1 + cosine)
            b2 = (1 + cosine) / 2
        } else {
            b0 = (1 - cosine) / 2
            b1 = 1 - cosine
            b2 = (1 - cosine) / 2
        }
        let a0 = 1 + alpha
        var filter = Biquad()
        filter.b0 = Float(b0 / a0)
        filter.b1 = Float(b1 / a0)
        filter.b2 = Float(b2 / a0)
        filter.a1 = Float((-2 * cosine) / a0)
        filter.a2 = Float((1 - alpha) / a0)
        return filter
    }
}

/// Slow attack, slow release. A short kick can rise above the running peak
/// instead of being pinned at 1, so the TV still hears the transient.
private struct Normalizer {
    var peak: Float = 1e-4
    var floor: Float = 1e-6

    mutating func normalize(_ energy: Float, dt: Float) -> Float {
        let dtSafe = max(dt, 0.0001)
        if energy > peak {
            peak += (energy - peak) * (1 - expf(-dtSafe / 0.45))
        } else {
            peak += (energy - peak) * (1 - expf(-dtSafe / 5.5))
        }
        peak = max(peak, 1e-8)
        if energy < floor {
            floor += (energy - floor) * (1 - expf(-dtSafe / 0.35))
        } else {
            floor += (energy - floor) * (1 - expf(-dtSafe / 8))
        }
        floor = min(floor, peak * 0.5)
        let span = max(peak - floor, peak * 0.22, 1e-8)
        return min(max((energy - floor) / span, 0), 1.8)
    }
}

/// Four bands plus a kick. Mutated only on the audio tap.
private struct BandAnalyzer {
    private var filters: [Biquad] = []
    private var builtRate: Double = 0
    private var gains = [Normalizer(), Normalizer(), Normalizer(), Normalizer()]
    private var loudGain = Normalizer()
    private var fluxGain = Normalizer()
    private var previousEnergy = [Float](repeating: 0, count: 4)
    private var previousBassPeak: Float = 0
    private var meanBassFlux: Float = 0
    private var onset: Float = 0
    private var refractory: Float = 0
    private var havePrevious = false

    mutating func consume(_ samples: [Float], sampleRate: Double) -> MicFeatures {
        let count = samples.count
        guard count > 0 else { return .zero }
        let rate = max(sampleRate, 8_000)
        if filters.count != 4 || abs(rate - builtRate) > 1 {
            filters = [
                Biquad.lowpass(cutoff: 110, sampleRate: rate, q: 0.707),
                Biquad.bandpass(cutoff: 300, sampleRate: rate, q: 0.85),
                Biquad.bandpass(cutoff: 1400, sampleRate: rate, q: 0.8),
                Biquad.highpass(cutoff: 5000, sampleRate: rate, q: 0.707)
            ]
            builtRate = rate
            havePrevious = false
        }

        var energy = [Float](repeating: 0, count: 4)
        var bassPeak: Float = 0
        var loudSum: Float = 0
        for sample in samples {
            loudSum += sample * sample
            for band in 0..<4 {
                let shaped = filters[band].process(sample)
                energy[band] += shaped * shaped
                if band == 0 {
                    bassPeak = max(bassPeak, abs(shaped))
                }
            }
        }
        let inv = 1 / Float(count)
        for band in 0..<4 {
            energy[band] *= inv
        }
        let dt = Float(Double(count) / rate)

        var fluxRaw: Float = 0
        if havePrevious {
            for band in 0..<4 {
                fluxRaw += max(0, energy[band] - previousEnergy[band])
            }
        } else {
            previousBassPeak = bassPeak
        }
        previousEnergy = energy
        havePrevious = true

        var shaped = [Float](repeating: 0, count: 4)
        for band in 0..<4 {
            shaped[band] = gains[band].normalize(energy[band], dt: dt)
        }
        let loudness = loudGain.normalize(loudSum * inv, dt: dt)
        let flux = fluxGain.normalize(fluxRaw, dt: dt)

        let bassFlux = max(0, bassPeak - previousBassPeak)
        previousBassPeak = bassPeak
        meanBassFlux += (bassFlux - meanBassFlux) * 0.06
        let gate = max(meanBassFlux * 1.7, 0.00008)
        if bassFlux > gate && shaped[0] > 0.28 && loudness > 0.12 && refractory <= 0 {
            let over = min(bassFlux / gate, 3)
            onset = min(1.7, 0.85 + 0.28 * over)
            refractory = 0.09
        } else {
            onset *= expf(-dt / 0.07)
            refractory = max(0, refractory - dt)
        }

        return MicFeatures(
            bass: shaped[0],
            lowMid: shaped[1],
            mid: shaped[2],
            high: shaped[3],
            loudness: loudness,
            onset: min(max(onset, 0), 1.7),
            flux: flux
        )
    }
}

/// Microphone, analysis, and the UDP link to whichever Apple TV is advertising.
/// `linked` is true only after the TV has answered, not when the socket opens.
final class MicCapture: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var linked = false
    @Published private(set) var status = "Tap Start. Allow the microphone and local network when asked."
    @Published private(set) var tvName = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var bassLevel: Float = 0
    @Published private(set) var activePreset = 0
    @Published private(set) var cycling = true
    @Published private(set) var pictureKnown = false
    @Published var sensitivity: Float = 1 {
        didSet {
            let finite = sensitivity.isFinite ? sensitivity : 1
            let clamped = min(max(finite, 0.5), 2)
            if clamped != sensitivity {
                sensitivity = clamped
                return
            }
            flag.lock()
            heldSensitivity = clamped
            flag.unlock()
        }
    }

    private let engine = AVAudioEngine()
    private let network = DispatchQueue(label: "app.wizuale.mic.send")
    private let flag = NSLock()
    private var analyzer = BandAnalyzer()
    private var tapInstalled = false
    private var sequence: UInt16 = 0
    private var commandSequence: UInt16 = 0
    private var heldSensitivity: Float = 1
    private var lastUI: CFTimeInterval = 0
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var connectedName = ""
    private var pendingAudio: Data?
    private var pendingCommands: [Data] = []
    private var lastCommand: Data?
    private var sending = false
    private var receiving = false
    private var wantsLink = false
    private var epoch = 0
    private var confirmed = false
    private var lastAck: CFTimeInterval = 0
    private var sendToken = 0
    private var expecting = false
    private var expectCycling = true
    private var expectPreset = 0
    private var expectUntil: CFTimeInterval = 0
    private var expectResends = 0
    private var startGeneration = 0
    private var interruption: NSObjectProtocol?

    init() {
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
                    self.status = "Microphone access is off. Enable Wizuale Mic in Settings → Privacy → Microphone."
                }
            }
        }
    }

    /// `-1` restores auto cycling. Any other value locks that preset on the TV.
    func selectPreset(_ choice: Int) {
        if choice < 0 {
            cycling = true
        } else {
            guard PresetLibrary.all.indices.contains(choice) else { return }
            cycling = false
            activePreset = choice
        }
        pictureKnown = true
        flag.lock()
        commandSequence &+= 1
        if commandSequence == 0 { commandSequence = 1 }
        let seq = commandSequence
        flag.unlock()
        let packet = MicWire.encodeCommand(sequence: seq, preset: Int16(clamping: choice))
        network.async { [weak self] in
            guard let self else { return }
            self.expecting = true
            self.expectCycling = choice < 0
            self.expectPreset = choice
            self.expectUntil = CACurrentMediaTime() + 0.45
            self.expectResends = 0
            self.enqueueCommand(packet)
        }
    }

    func stop() {
        startGeneration += 1
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
            return
        }

        analyzer = BandAnalyzer()
        sequence = 0
        lastUI = 0
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer)
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
        network.async { [weak self] in
            self?.startBrowser()
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
        tearDown(status: "Audio was interrupted. Tap Start to listen again.")
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 1, buffer.frameLength > 0 else { return }
        let samples = monoFloats(from: buffer)
        guard !samples.isEmpty else { return }
        let features = analyzer.consume(samples, sampleRate: rate)
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        let packet = MicWire.encodeAudio(
            sequence: sequence,
            features: features,
            sensitivity: currentSensitivity()
        )
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
            }
        }
    }

    private func monoFloats(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        if let channels = buffer.floatChannelData {
            let count = Int(buffer.format.channelCount)
            guard count > 0 else { return [] }
            var mono = [Float](repeating: 0, count: frames)
            let scale = 1 / Float(count)
            for channel in 0..<count {
                let samples = channels[channel]
                for frame in 0..<frames {
                    mono[frame] += samples[frame] * scale
                }
            }
            return mono
        }
        return convertedMono(from: buffer, frames: frames)
    }

    private func convertedMono(from buffer: AVAudioPCMBuffer, frames: Int) -> [Float] {
        guard
            let desired = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: buffer.format.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: buffer.format, to: desired),
            let converted = AVAudioPCMBuffer(pcmFormat: desired, frameCapacity: AVAudioFrameCount(frames))
        else { return [] }
        var fed = false
        var error: NSError?
        let input: AVAudioConverterInputBlock = { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: converted, error: &error, withInputFrom: input)
        guard error == nil, let channels = converted.floatChannelData else { return [] }
        let got = Int(converted.frameLength)
        guard got > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channels[0], count: got))
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

    private func startBrowser() {
        guard linkWanted() else { return }
        browser?.cancel()
        let params = NWParameters.udp
        params.includePeerToPeer = true
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
                if let data, let packet = MicWire.decode(data), case .ack(let preset, let cycling) = packet {
                    self.noteAck(preset: preset, cycling: cycling)
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
        let matches = expectCycling ? ackCycling : (!ackCycling && index == expectPreset)
        if expecting && !matches && CACurrentMediaTime() < expectUntil {
            publish(status: "The picture is following this phone.", tv: name, linked: true)
            return
        }
        if expecting && !matches && expectResends < 1 {
            expectResends += 1
            expectUntil = CACurrentMediaTime() + 0.45
            if let lastCommand {
                pendingCommands.append(lastCommand)
                pump()
            }
            publish(status: "The picture is following this phone.", tv: name, linked: true)
            return
        }
        expecting = false
        let picture = PresetLibrary.all.indices.contains(index) ? PresetLibrary.all[index].name : "this picture"
        let detail = ackCycling ? "Auto is on. Showing \(picture)." : "Locked on \(picture)."
        publish(
            status: detail,
            tv: name,
            linked: true,
            preset: index,
            cycling: ackCycling,
            known: true
        )
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

    private func enqueueCommand(_ data: Data) {
        lastCommand = data
        pendingCommands.append(data)
        if pendingCommands.count > 6 {
            pendingCommands.removeFirst(pendingCommands.count - 6)
        }
        pump()
    }

    private func pump() {
        guard !sending, let connection, connection.state == .ready else { return }
        let data: Data
        if !pendingCommands.isEmpty {
            data = pendingCommands.removeFirst()
        } else if let audio = pendingAudio {
            pendingAudio = nil
            data = audio
        } else {
            return
        }
        sending = true
        let token = sendToken
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.network.async {
                guard let self, self.sendToken == token else { return }
                self.sending = false
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
        sendToken += 1
        connection?.cancel()
        connection = nil
        connectedName = ""
        pendingAudio = nil
        pendingCommands.removeAll()
        sending = false
        receiving = false
        confirmed = false
        lastAck = 0
    }

    private func publish(
        status: String? = nil,
        tv: String? = nil,
        linked: Bool? = nil,
        preset: Int? = nil,
        cycling: Bool? = nil,
        known: Bool? = nil
    ) {
        let epoch = epochNow()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.epochNow() == epoch else { return }
            if let status { self.status = status }
            if let tv { self.tvName = tv }
            if let linked { self.linked = linked }
            if let preset, PresetLibrary.all.indices.contains(preset) {
                self.activePreset = preset
            }
            if let cycling { self.cycling = cycling }
            if let known { self.pictureKnown = known }
        }
    }
}
