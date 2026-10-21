import Darwin
import Foundation
import Network
import QuartzCore
import UIKit

/// What one frame should do with the phone's audio. `presence` fades to 0
/// after the packets stop so the picture eases back to the beat clock.
struct MicDrive: Sendable {
    var onset: Float
    var bass: Float
    var lowMid: Float
    var mid: Float
    var high: Float
    var loudness: Float
    var flux: Float
    var presence: Float

    static let silent = MicDrive(
        onset: 0, bass: 0, lowMid: 0, mid: 0, high: 0, loudness: 0, flux: 0, presence: 0
    )
}

/// Advertises `_wizuale._udp` and keeps the newest packet. The draw loop calls
/// `sample` on its own thread; the listener queue only stores bytes.
final class MicReceiver: @unchecked Sendable {
    var onStatus: (@Sendable (Bool, String) -> Void)?

    private let queue = DispatchQueue(label: "app.wizuale.mic.listen")
    private let lock = NSLock()
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: NWConnection] = [:]
    private var latest = MicFeatures.zero
    private var latestSequence: UInt16 = 0
    private var havePacket = false
    private var lastArrival: CFTimeInterval = 0

    private var onset: Float = 0
    private var bass: Float = 0
    private var lowMid: Float = 0
    private var mid: Float = 0
    private var high: Float = 0
    private var loudness: Float = 0
    private var flux: Float = 0
    private var presence: Float = 0
    private var appliedSequence: UInt16 = 0
    private var haveApplied = false
    private var reportedLive = false

    func start() {
        let raw = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.bonjourName(raw.isEmpty ? "Wizuale" : raw)
        queue.async { [weak self] in
            self?.listen(as: name)
        }
    }

    /// Smoothed features for this frame. Call once per draw.
    func sample(dt: Float) -> MicDrive {
        let dtSafe = min(max(dt, 0), 0.1)
        lock.lock()
        let packet = latest
        let sequence = latestSequence
        let age = havePacket ? CACurrentMediaTime() - lastArrival : 1_000
        if age > 1 {
            haveApplied = false
        }
        let fresh = age < 0.30
        let isNew = fresh && (!haveApplied || sequence != appliedSequence)
        if isNew {
            if packet.onset > onset { onset = packet.onset }
            haveApplied = true
            appliedSequence = sequence
        }
        let target = fresh ? packet : MicFeatures.zero
        lock.unlock()

        onset *= expf(-dtSafe / 0.075)
        bass = follow(bass, target.bass, dt: dtSafe, attack: 0.02, release: 0.10)
        lowMid = follow(lowMid, target.lowMid, dt: dtSafe, attack: 0.03, release: 0.12)
        mid = follow(mid, target.mid, dt: dtSafe, attack: 0.03, release: 0.12)
        high = follow(high, target.high, dt: dtSafe, attack: 0.02, release: 0.08)
        loudness = follow(loudness, target.loudness, dt: dtSafe, attack: 0.03, release: 0.14)
        flux = follow(flux, target.flux, dt: dtSafe, attack: 0.02, release: 0.08)

        let presenceTarget: Float = fresh ? 1 : 0
        let presenceTau: Float = fresh ? 0.05 : 0.40
        presence = follow(presence, presenceTarget, dt: dtSafe, attack: presenceTau, release: presenceTau)

        let live = fresh || presence > 0.08
        var shouldReport: (Bool, String)?
        lock.lock()
        if live != reportedLive {
            reportedLive = live
            shouldReport = (live, live ? "Mic" : "")
        }
        lock.unlock()
        if let shouldReport, let onStatus {
            DispatchQueue.main.async {
                onStatus(shouldReport.0, shouldReport.1)
            }
        }

        return MicDrive(
            onset: onset,
            bass: bass,
            lowMid: lowMid,
            mid: mid,
            high: high,
            loudness: loudness,
            flux: flux,
            presence: min(max(presence, 0), 1)
        )
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
    }

    private func receive(_ connection: NWConnection, key: ObjectIdentifier) {
        connection.receiveMessage { [weak self] data, _, _, error in
            self?.queue.async {
                guard let self, self.peers[key] != nil else { return }
                if let data, let decoded = MicWire.decode(data) {
                    self.store(decoded.features, sequence: decoded.sequence)
                }
                if error != nil {
                    self.drop(key)
                    return
                }
                self.receive(connection, key: key)
            }
        }
    }

    private func store(_ features: MicFeatures, sequence: UInt16) {
        lock.lock()
        latest = features
        latestSequence = sequence
        havePacket = true
        lastArrival = CACurrentMediaTime()
        lock.unlock()
    }

    private func drop(_ key: ObjectIdentifier) {
        peers[key]?.cancel()
        peers[key] = nil
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
