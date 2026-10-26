import Foundation
import QuartzCore

/// What is actually fed into libprojectM each frame (for debug and routing).
enum ProjectMAudioFeedState: String, Sendable {
    /// TV mic input is Off — silence only.
    case none
    /// Phone/Continuity selected but FIFO is still filling (transport is up).
    case idle
    /// Mono PCM from Wizuale Mic over Wi‑Fi.
    case phonePCM
    /// Mono PCM from Continuity Microphone on the TV.
    case continuityPCM
    /// No live stream — feeding silence to drain projectM's internal buffer.
    case fallback
}

/// PCM queue from the mic receiver to the GL draw loop.
final class ProjectMAudioHub: @unchecked Sendable {
    struct Metrics: Sendable {
        var fifoSamples: Int
        var fifoMs: Float
        var lastChunk: Int
        var rms: Float
        var agcGain: Float
        /// UDP PCM still arriving (hysteresis — see `transportDropTimeout`).
        var streamLive: Bool
        var accentOnset: Float
        var feedState: ProjectMAudioFeedState
        var micSource: MicInputSource
        var pcmPacketsPerSec: Float
        var gapAvgMs: Float
        var gapMaxMs: Float
        var underrunTotal: UInt32
        /// RMS of last enqueued PCM (int16 → float), before TV AGC/shaping.
        var pcmInRms: Float
    }

    private let lock = NSLock()
    private var fifo: [Float] = []
    private var rate: Float = 48_000
    private var sensitivity: Float = MicTuning.loadSensitivity()
    private var latencyMs: Int = MicTuning.loadLatency()
    /// TV monotonic clock — last PCM datagram arrival.
    private var lastArrival: CFTimeInterval = 0
    private var transportUp = false

    private var lastFeed: CFTimeInterval = 0
    private var meanSquare: Float = 0
    private var agcGain: Float = 6
    private var fastEnv: Float = 0
    private var slowEnv: Float = 0
    private var accentEnvelope: Float = 0
    private var lastSample: Float = 0
    private var underrunDecay: Float = 0
    private var underrunTotal: UInt32 = 0

    private var windowBegin: CFTimeInterval = 0
    private var windowPackets = 0
    private var displayedPPS: Float = 0
    private var gapSumMs: Float = 0
    private var gapCount = 0
    private var gapMaxMs: Float = 0
    private var lastEnqueueRms: Float = 0

    private var lastMetrics = Metrics(
        fifoSamples: 0, fifoMs: 0, lastChunk: 0, rms: 0, agcGain: 6,
        streamLive: false, accentOnset: 0, feedState: .fallback,
        micSource: .phone, pcmPacketsPerSec: 0, gapAvgMs: 0, gapMaxMs: 0,
        underrunTotal: 0, pcmInRms: 0
    )

    static let primeFrameCount: Float = 2
    /// Jitter absorption — larger than phone burst spacing.
    static let maxFifoSeconds: Float = 0.85
    static let targetJitterMs: Float = 70
    static let minPrimeMs: Float = 20
    static let targetRMS: Float = 0.22
    static let maxGain: Float = 64
    static let noiseFloorRMS: Float = 0.0004
    /// No PCM this long ⇒ stream dead (silence drain).
    static let transportDropTimeout: CFTimeInterval = 1.75
    /// Never drain more than ~1.2 frames of audio per GL tick (steady ~800 smp @ 60 Hz).
    static let maxConsumeFrameFactor: Float = 1.2

    func setBeatSensitivity(_ value: Float) {
        lock.lock()
        sensitivity = MicTuning.clampSensitivity(value)
        lock.unlock()
    }

    func setLatency(_ ms: Int) {
        lock.lock()
        latencyMs = MicTuning.clampLatency(ms)
        lock.unlock()
    }

    func enqueue(sampleRate: Float, samples: [Int16], now: CFTimeInterval = CACurrentMediaTime()) {
        guard !samples.isEmpty, sampleRate > 1000 else { return }
        lock.lock()
        if abs(sampleRate - rate) > 1 {
            rate = sampleRate
            fifo.removeAll(keepingCapacity: true)
        }
        if lastArrival > 0 {
            let gapMs = Float((now - lastArrival) * 1000)
            if gapMs.isFinite, gapMs >= 0 {
                gapSumMs += gapMs
                gapCount += 1
                gapMaxMs = max(gapMaxMs, gapMs)
            }
        }
        lastArrival = now
        transportUp = true

        if windowBegin == 0 {
            windowBegin = now
        }
        windowPackets += 1
        let windowElapsed = now - windowBegin
        if windowElapsed >= 1.0 {
            displayedPPS = Float(windowPackets) / Float(windowElapsed)
            windowPackets = 0
            windowBegin = now
            gapSumMs = 0
            gapCount = 0
            gapMaxMs = 0
        }

        fifo.reserveCapacity(fifo.count + samples.count)
        for s in samples { fifo.append(Float(s) / 32768) }
        lastEnqueueRms = MicPCM.rmsInt16(samples)
        let cap = Int(Self.maxFifoSeconds * rate)
        if fifo.count > cap { fifo.removeFirst(fifo.count - cap) }
        lock.unlock()
    }

    func metricsSnapshot() -> Metrics {
        lock.lock()
        let snap = lastMetrics
        lock.unlock()
        return snap
    }

    /// Hands this frame's audio to `sink` (mono floats in -1...1). Call once per frame.
    func feed(
        accent: MicDrive,
        micSource: MicInputSource,
        now: CFTimeInterval = CACurrentMediaTime(),
        into sink: ([Float]) -> Void
    ) {
        let dt = Float(lastFeed > 0 ? min(max(now - lastFeed, 0), 0.1) : 1.0 / 60.0)
        lastFeed = now

        lock.lock()
        let r = rate
        let sens = sensitivity
        let latency = latencyMs
        if lastArrival > 0, now - lastArrival > Self.transportDropTimeout {
            transportUp = false
            fifo.removeAll(keepingCapacity: true)
            softenShapingState()
            lastArrival = 0
        }
        let transportLive = transportUp
        let paceDt = min(dt, 1.0 / 55.0)
        let frameSamples = max(1, Int((r * paceDt).rounded()))
        var due = frameSamples
        if latency < 0 {
            let boost = min(frameSamples / 4, max(0, -latency) * Int(r) / 1000 / 16)
            due += boost
        }
        let maxDue = max(1, Int(Float(frameSamples) * Self.maxConsumeFrameFactor))
        due = min(due, maxDue)
        var chunk: [Float] = []
        var feedState: ProjectMAudioFeedState = .fallback
        var underrunThisFrame = false

        switch micSource {
        case .off:
            feedState = .none
        case .phone:
            if !transportLive {
                feedState = .fallback
            } else {
                feedState = .phonePCM
                let take = min(due, fifo.count)
                if take < due {
                    underrunThisFrame = true
                }
                if take > 0 {
                    chunk = Array(fifo.prefix(take))
                    fifo.removeFirst(take)
                }
            }
        case .continuity:
            if !transportLive {
                feedState = .fallback
            } else {
                feedState = .continuityPCM
                let take = min(due, fifo.count)
                if take < due {
                    underrunThisFrame = true
                }
                if take > 0 {
                    chunk = Array(fifo.prefix(take))
                    fifo.removeFirst(take)
                }
            }
        }
        if underrunThisFrame {
            underrunTotal += 1
        }
        let fifoCount = fifo.count
        let pps = displayedPPS
        let gapAvg = gapCount > 0 ? gapSumMs / Float(gapCount) : 0
        let gapMax = gapMaxMs
        let underruns = underrunTotal
        let pcmIn = lastEnqueueRms
        lock.unlock()

        var out: [Float]
        switch feedState {
        case .phonePCM, .continuityPCM:
            if chunk.isEmpty {
                out = underrunHold(count: due)
            } else {
                out = shape(chunk, dt: dt, rate: r, sensitivity: sens)
                if let tail = out.last {
                    lastSample = tail
                    underrunDecay = 1
                }
                if out.count < due {
                    out.append(contentsOf: underrunHold(count: due - out.count))
                }
            }
        case .none, .idle, .fallback:
            out = [Float](repeating: 0, count: due)
            decayShapingState(dt: dt)
            underrunDecay = 0
        }

        let accentActive = feedState == .phonePCM || feedState == .continuityPCM
        if accentActive {
            applyAccent(&out, accent: accent)
        } else {
            accentEnvelope *= 0.9
        }
        sink(out)

        lock.lock()
        lastMetrics = Metrics(
            fifoSamples: fifoCount,
            fifoMs: fifoCount > 0 ? Float(fifoCount) / r * 1000 : 0,
            lastChunk: out.count,
            rms: sqrtf(max(meanSquare, 0)),
            agcGain: agcGain,
            streamLive: transportLive,
            accentOnset: accentEnvelope,
            feedState: feedState,
            micSource: micSource,
            pcmPacketsPerSec: pps,
            gapAvgMs: gapAvg,
            gapMaxMs: gapMax,
            underrunTotal: underruns,
            pcmInRms: pcmIn
        )
        lock.unlock()
    }

    private func underrunHold(count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        let decayPerSample: Float = 0.9992
        for i in 0..<count {
            underrunDecay *= decayPerSample
            out[i] = lastSample * underrunDecay
        }
        return out
    }

    private func softenShapingState() {
        meanSquare *= 0.2
        fastEnv *= 0.2
        slowEnv *= 0.2
        accentEnvelope = 0
        lastSample = 0
        underrunDecay = 0
    }

    private func decayShapingState(dt: Float) {
        let decay = expf(-dt / 0.12)
        meanSquare *= decay
        fastEnv *= decay
        slowEnv *= decay
        agcGain += (1 - agcGain) * (1 - decay)
    }

    private func applyAccent(_ samples: inout [Float], accent: MicDrive) {
        guard accent.presence > 0.05 else {
            accentEnvelope *= 0.9
            return
        }
        let hit = min(
            accent.onset * Float(1.5) + accent.bass * Float(0.4),
            Float(2.8)
        )
        accentEnvelope = max(accentEnvelope * 0.82, hit)
        let bump = accentEnvelope * 0.24 * accent.presence
        guard bump > 0.01 else { return }
        for i in 0..<samples.count {
            samples[i] = tanhf(samples[i] + bump)
        }
        accentEnvelope *= 0.9
    }

    private func shape(_ input: [Float], dt: Float, rate: Float, sensitivity: Float) -> [Float] {
        let fastAttack = 1 as Float - expf(-1 / (0.0015 as Float * rate))
        let fastRelease = 1 as Float - expf(-1 / (0.040 as Float * rate))
        let slowCoef = 1 as Float - expf(-1 / (0.180 as Float * rate))
        let rmsCoef = 1 as Float - expf(-1 / (0.35 as Float * rate))
        let punch: Float = 1.15 * sensitivity
        var out = [Float](repeating: 0, count: input.count)
        let gain = agcGain
        for i in 0..<input.count {
            let x = input[i]
            let a = abs(x)
            fastEnv += (a - fastEnv) * (a > fastEnv ? fastAttack : fastRelease)
            slowEnv += (a - slowEnv) * slowCoef
            meanSquare += (x * x - meanSquare) * rmsCoef
            let ratio = slowEnv > 1e-6 ? fastEnv / slowEnv : 1 as Float
            let boost = 1 as Float + punch * min(max(ratio - 1, 0), 4)
            out[i] = tanhf(x * gain * boost)
        }
        let rms = sqrtf(meanSquare)
        if rms > Self.noiseFloorRMS {
            let desired = min(max(Self.targetRMS / rms, 1), Self.maxGain)
            let attack: Float = rms > Self.targetRMS * 0.9 ? 0.08 as Float : 0.35 as Float
            agcGain += (desired - agcGain) * (1 as Float - expf(-dt / attack))
        }
        return out
    }
}
