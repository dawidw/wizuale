import Darwin
import Foundation
import Network
import os
import QuartzCore
import UIKit

/// What one frame should do with the microphone. `presence` fades to 0
/// after the packets stop so the picture eases back to the beat clock.
/// Bass, kick, and highs are already scaled by the sensitivity slider.
/// `drop` is the held Drop look. `dropPunch` is the one-shot zoom.
struct MicDrive: Sendable {
    var onset: Float
    var bass: Float
    var lowMid: Float
    var mid: Float
    var high: Float
    var loudness: Float
    var flux: Float
    var presence: Float
    var drop: Float
    var dropPunch: Float

    static let silent = MicDrive(
        onset: 0, bass: 0, lowMid: 0, mid: 0, high: 0, loudness: 0, flux: 0,
        presence: 0, drop: 0, dropPunch: 0
    )
}

/// Advertises `_wizuale._udp`, keeps a short delay line of analysis frames,
/// and answers with the picture that is on screen. The draw loop calls
/// `sample` on its own thread. The listener queue stores bytes and sends acks.
final class MicReceiver: @unchecked Sendable {
    private let log = Logger(subsystem: "app.wizuale", category: "MicTV")

    var onStatus: (@Sendable (Bool, String) -> Void)?
    /// Phone preset choice. `-1` means go back to auto. Called on the main queue.
    var onCommand: (@Sendable (Int) -> Void)?
    /// Latency in milliseconds and sensitivity. Called on the main queue when a settings packet arrives.
    var onTuning: (@Sendable (Int, Float) -> Void)?
    /// Whether album art may tint the picture. Called on the main queue when a settings packet says so.
    var onAlbumArt: (@Sendable (Bool) -> Void)?
    /// Uniform zoom, about 0.5...2. Called on the main queue when a settings packet says so.
    var onZoom: (@Sendable (Float) -> Void)?

    private struct Stamp {
        var features: MicFeatures
        var sequence: UInt16
        var time: CFTimeInterval
    }

    private let queue = DispatchQueue(label: "app.wizuale.mic.listen")
    private let lock = NSLock()
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: NWConnection] = [:]
    private var stamps: [Stamp] = []
    private let stampLimit = 96
    private var havePacket = false
    private var lastArrival: CFTimeInterval = 0
    private var sensitivity: Float
    private var latencyMs: Int
    private var albumArt: Bool
    private var zoom: Float
    private var source: MicInputSource
    private var localSequence: UInt16 = 0
    private var dropTarget: Float = 0
    private var lastBoostAt: CFTimeInterval = 0

    private var onset: Float = 0
    private var bass: Float = 0
    private var lowMid: Float = 0
    private var mid: Float = 0
    private var high: Float = 0
    private var loudness: Float = 0
    private var flux: Float = 0
    private var presence: Float = 0
    private var dropLevel: Float = 0
    private var dropPunch: Float = 0
    private var punchArmed = true
    private var appliedSequence: UInt16 = 0
    private var haveApplied = false
    private var reportedLive = false

    private var shownIndex = 0
    private var shownCycling = true
    private var lastAckTime: CFTimeInterval = 0
    /// Last phone peer that sent a packet. Replies go here first so acks land on the
    /// same NWConnection the Mic app is receiving on.
    private var lastPeerKey: ObjectIdentifier?
    private var ackHeartbeat: DispatchWorkItem?

    private let hitCap: Float = 3.5

    init() {
        sensitivity = MicTuning.loadSensitivity()
        latencyMs = MicTuning.loadLatency()
        albumArt = MicTuning.loadAlbumArt()
        zoom = MicTuning.loadZoom()
        source = MicTuning.loadSource()
    }

    func start() {
        let raw = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.bonjourName(raw.isEmpty ? "Wizuale" : raw)
        queue.async { [weak self] in
            self?.listen(as: name)
        }
    }

    func setSource(_ next: MicInputSource) {
        lock.lock()
        source = next
        stamps.removeAll()
        havePacket = false
        haveApplied = false
        localSequence = 0
        lock.unlock()
        MicTuning.saveSource(next)
    }

    func setLatency(_ ms: Int) {
        let clamped = MicTuning.clampLatency(ms)
        lock.lock()
        latencyMs = clamped
        lock.unlock()
        MicTuning.saveLatency(clamped)
    }

    func setSensitivity(_ value: Float) {
        let clamped = MicTuning.clampSensitivity(value)
        lock.lock()
        sensitivity = clamped
        lock.unlock()
        MicTuning.saveSensitivity(clamped)
    }

    /// The picture the phone should be told about. Safe from the main actor.
    func setShown(index: Int, cycling: Bool) {
        lock.lock()
        shownIndex = index
        shownCycling = cycling
        lock.unlock()
        queue.async { [weak self] in
            self?.sendAck(force: true)
        }
    }

    /// Continuity tap. Ignored unless that source is selected.
    func ingestLocal(_ features: MicFeatures) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let accept = self.source == .continuity
            self.lock.unlock()
            guard accept else { return }
            self.localSequence &+= 1
            if self.localSequence == 0 { self.localSequence = 1 }
            self.push(features, sequence: self.localSequence)
        }
    }

    /// Smoothed features for this frame. Call once per draw.
    func sample(dt: Float) -> MicDrive {
        let dtSafe = min(max(dt, 0), 0.1)
        let now = CACurrentMediaTime()
        lock.lock()
        let sourceNow = source
        let sens = sensitivity
        let latency = latencyMs
        let boostIn = dropTarget
        let boostAt = lastBoostAt
        let arrivedAt = lastArrival
        let arriving = sourceNow != .off && havePacket && (now - arrivedAt) < 0.30
        var chosen: Stamp?
        if sourceNow != .off {
            let delay = latency < 0 ? 0.0 : Double(latency) / 1000
            let readTime = now - delay
            for stamp in stamps.reversed() {
                if stamp.time <= readTime {
                    if readTime - stamp.time <= 0.30 {
                        chosen = stamp
                    }
                    break
                }
            }
        }
        lock.unlock()

        let packet = chosen?.features ?? MicFeatures.zero
        let sequence = chosen?.sequence ?? 0
        let fresh = arriving || chosen != nil
        let isNew = chosen != nil && (!haveApplied || sequence != appliedSequence)
        if isNew {
            if packet.onset > onset { onset = packet.onset }
            haveApplied = true
            appliedSequence = sequence
        }
        if !fresh && now - arrivedAt > 1 {
            haveApplied = false
        }

        let target = fresh ? packet : MicFeatures.zero
        onset *= expf(-dtSafe / 0.14)
        bass = follow(bass, target.bass, dt: dtSafe, attack: 0.012, release: 0.30)
        lowMid = follow(lowMid, target.lowMid, dt: dtSafe, attack: 0.018, release: 0.24)
        mid = follow(mid, target.mid, dt: dtSafe, attack: 0.02, release: 0.16)
        high = follow(high, target.high, dt: dtSafe, attack: 0.015, release: 0.09)
        loudness = follow(loudness, target.loudness, dt: dtSafe, attack: 0.02, release: 0.22)
        flux = follow(flux, target.flux, dt: dtSafe, attack: 0.015, release: 0.10)

        let presenceTarget: Float = fresh ? 1 : 0
        let presenceTau: Float = fresh ? 0.05 : 0.40
        presence = follow(presence, presenceTarget, dt: dtSafe, attack: presenceTau, release: presenceTau)

        let boostAge = now - boostAt
        let boostGoal: Float = (boostAt > 0 && boostAge < 1.5) ? boostIn : 0
        if boostGoal > 0.6 && punchArmed {
            dropPunch = 1
            punchArmed = false
        }
        if boostGoal < 0.25 {
            punchArmed = true
        }
        dropLevel = follow(dropLevel, boostGoal, dt: dtSafe, attack: 0.05, release: 0.75)
        dropPunch *= expf(-dtSafe / 0.20)

        let live = fresh || presence > 0.08
        let label: String
        switch sourceNow {
        case .continuity: label = "Continuity"
        case .phone: label = "Mic"
        case .off: label = ""
        }
        var shouldReport: (Bool, String)?
        lock.lock()
        if live != reportedLive || (live && label != lastReportedName) {
            reportedLive = live
            lastReportedName = live ? label : ""
            shouldReport = (live, live ? label : "")
        }
        lock.unlock()
        if let shouldReport, let onStatus {
            let report = shouldReport
            DispatchQueue.main.async {
                onStatus(report.0, report.1)
            }
        }

        return MicDrive(
            onset: hit(onset, sens),
            bass: hit(bass, sens),
            lowMid: hit(lowMid, sens),
            mid: shaped(mid),
            high: hit(high, sens),
            loudness: shaped(loudness),
            flux: hit(flux, sens),
            presence: min(max(presence, 0), 1),
            drop: min(max(dropLevel, 0), 1),
            dropPunch: min(max(dropPunch, 0), 1.5)
        )
    }

    private var lastReportedName = ""

    /// Opens the top of the curve. Sensitivity scales bass, kick, and highs.
    /// The shader does not multiply it again. The cap leaves room for 3×.
    private func hit(_ value: Float, _ sensitivity: Float) -> Float {
        min(shaped(value) * max(sensitivity, 0), hitCap)
    }

    private func shaped(_ value: Float) -> Float {
        powf(min(max(value, 0), MicWire.gainCeiling), 0.85)
    }

    private func follow(_ current: Float, _ target: Float, dt: Float, attack: Float, release: Float) -> Float {
        let tau = max(target > current ? attack : release, 0.0001)
        let mixAmt = 1 - expf(-dt / tau)
        return current + (target - current) * mixAmt
    }

    private func listen(as name: String) {
        if listener != nil { return }
        let params = NWParameters.udp
        params.includePeerToPeer = true
        do {
            let created = try NWListener(using: params)
            created.service = NWListener.Service(name: name, type: MicWire.serviceType)
            created.stateUpdateHandler = { [weak self] state in
                self?.queue.async {
                    self?.listenerState(state, name: name)
                }
            }
            created.newConnectionHandler = { [weak self] connection in
                self?.queue.async {
                    self?.accept(connection)
                }
            }
            created.start(queue: queue)
            listener = created
            scheduleAckHeartbeat()
        } catch {
            listener = nil
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.listen(as: name)
            }
        }
    }

    private func listenerState(_ state: NWListener.State, name: String) {
        if case .failed = state {
            // The listener is already dead. Cancelling it would deliver `.cancelled`
            // after a replacement had started, and that would drop the new one.
            listener = nil
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.listen(as: name)
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        peers[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                if case .failed = state { self?.drop(key) }
                if case .cancelled = state { self?.drop(key) }
            }
        }
        connection.start(queue: queue)
        receive(connection, key: key)
        sendAck(force: true)
    }

    private func receive(_ connection: NWConnection, key: ObjectIdentifier) {
        connection.receiveMessage { [weak self] data, _, _, error in
            self?.queue.async {
                guard let self, self.peers[key] != nil else { return }
                if let data {
                    self.ingest(data, from: key)
                }
                if error != nil {
                    self.drop(key)
                    return
                }
                self.receive(connection, key: key)
            }
        }
    }

    private func ingest(_ data: Data, from key: ObjectIdentifier) {
        lastPeerKey = key
        guard let packet = MicWire.decode(data) else { return }
        switch packet {
        case .audio(let sequence, let features, let sens):
            adoptSensitivity(sens)
            lock.lock()
            let accept = source == .phone
            lock.unlock()
            if accept {
                push(features, sequence: sequence)
            }
            sendAck(force: false)
        case .command(_, let preset):
            apply(preset)
            sendAck(force: true)
            let choice = Int(preset)
            let handler = onCommand
            if let handler {
                DispatchQueue.main.async {
                    handler(choice)
                }
            }
        case .settings(_, let latency, let sens, let art, let zoom):
            adoptSettings(latencyMs: Int(latency), sensitivity: sens, albumArt: art, zoom: zoom)
            sendAck(force: true)
        case .boost(_, let amount):
            lock.lock()
            dropTarget = amount
            lastBoostAt = CACurrentMediaTime()
            lock.unlock()
        case .ack(_, _, _, _):
            break
        }
    }

    private func adoptSensitivity(_ value: Float) {
        let clamped = MicTuning.clampSensitivity(value)
        lock.lock()
        let changed = abs(clamped - sensitivity) > 0.001
        let ms = latencyMs
        if changed { sensitivity = clamped }
        lock.unlock()
        guard changed else { return }
        MicTuning.saveSensitivity(clamped)
        let handler = onTuning
        DispatchQueue.main.async {
            handler?(ms, clamped)
        }
    }

    private func adoptSettings(latencyMs ms: Int, sensitivity sens: Float, albumArt art: Bool?, zoom scale: Float?) {
        let clampedMs = MicTuning.clampLatency(ms)
        let clamped = MicTuning.clampSensitivity(sens)
        let clampedZoom = MicTuning.clampZoom(scale ?? MicTuning.zoomDefault)
        lock.lock()
        latencyMs = clampedMs
        sensitivity = clamped
        let zoomChanged = abs(clampedZoom - zoom) > 0.001
        zoom = clampedZoom
        var artChanged = false
        if let art, art != albumArt {
            albumArt = art
            artChanged = true
        }
        lock.unlock()
        MicTuning.saveLatency(clampedMs)
        MicTuning.saveSensitivity(clamped)
        MicTuning.saveZoom(clampedZoom)
        if artChanged, let art {
            MicTuning.saveAlbumArt(art)
        }
        let handler = onTuning
        let artHandler = onAlbumArt
        let zoomHandler = onZoom
        DispatchQueue.main.async {
            handler?(clampedMs, clamped)
            if artChanged, let art {
                artHandler?(art)
            }
            if zoomChanged {
                zoomHandler?(clampedZoom)
            }
        }
    }

    private func push(_ features: MicFeatures, sequence: UInt16) {
        let now = CACurrentMediaTime()
        lock.lock()
        stamps.append(Stamp(features: features, sequence: sequence, time: now))
        if stamps.count > stampLimit {
            stamps.removeFirst(stamps.count - stampLimit)
        }
        havePacket = true
        lastArrival = now
        lock.unlock()
    }

    private func apply(_ preset: Int16) {
        lock.lock()
        if preset < 0 {
            shownCycling = true
        } else if PresetLibrary.all.indices.contains(Int(preset)) {
            shownIndex = Int(preset)
            shownCycling = false
        }
        lock.unlock()
    }

    private func sendAck(force: Bool) {
        let now = CACurrentMediaTime()
        if !force && now - lastAckTime < 0.12 { return }
        lastAckTime = now
        lock.lock()
        let preset = Int16(clamping: shownIndex)
        let cycling = shownCycling
        let ms = latencyMs
        let sens = sensitivity
        lock.unlock()
        let packet = MicWire.encodeAck(preset: preset, cycling: cycling, latencyMs: ms, sensitivity: sens)
        let targets: [NWConnection]
        if let lastPeerKey, let peer = peers[lastPeerKey] {
            targets = [peer]
        } else {
            targets = Array(peers.values)
        }
        guard !targets.isEmpty else { return }
        log.debug("ack sent preset=\(preset) cycling=\(cycling) peers=\(targets.count)")
        for connection in targets {
            connection.send(content: packet, completion: .contentProcessed { _ in })
        }
    }

    private func scheduleAckHeartbeat() {
        ackHeartbeat?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.listener != nil else { return }
            self.sendAck(force: true)
            self.scheduleAckHeartbeat()
        }
        ackHeartbeat = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func drop(_ key: ObjectIdentifier) {
        peers[key]?.cancel()
        peers[key] = nil
        if lastPeerKey == key {
            lastPeerKey = nil
        }
    }

    private static func bonjourName(_ raw: String) -> String {
        if raw.utf8.count <= 63 { return raw }
        var bytes = Data()
        for byte in raw.utf8 {
            if bytes.count >= 60 { break }
            bytes.append(byte)
        }
        while let last = bytes.last, last & 0b1100_0000 == 0b1000_0000 {
            bytes.removeLast()
        }
        return String(data: bytes, encoding: .utf8) ?? "Wizuale"
    }
}
