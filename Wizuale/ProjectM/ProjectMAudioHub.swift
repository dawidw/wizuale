import Foundation
import QuartzCore

/// What is actually fed into libprojectM each frame (for debug and routing).
enum ProjectMAudioFeedState: String, Sendable {
    /// TV mic input is Off — silence only.
    case none
    /// Phone/Continuity selected but no live packets yet (or FIFO priming).
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
        var streamLive: Bool
        var accentOnset: Float
        var feedState: ProjectMAudioFeedState
        var micSource: MicInputSource
    }

    private let lock = NSLock()
    private var fifo: [Float] = []
    private var rate: Float = 48_000
    private var sensitivity: Float = MicTuning.loadSensitivity()
    private var latencyMs: Int = MicTuning.loadLatency()
    private var lastArrival: CFTimeInterval = 0
    private var wasStreamLive = false

    private var lastFeed: CFTimeInterval = 0
    private var meanSquare: Float = 0
    private var agcGain: Float = 6
    private var fastEnv: Float = 0
    private var slowEnv: Float = 0
    private var accentEnvelope: Float = 0
    private var lastMetrics = Metrics(
        fifoSamples: 0, fifoMs: 0, lastChunk: 0, rms: 0, agcGain: 6,
        streamLive: false, accentOnset: 0, feedState: .fallback,
        micSource: .phone
    )

    static let primeFrameCount: Float = 2
    static let maxFifoSeconds: Float = 0.35
    static let targetRMS: Float = 0.22
    static let maxGain: Float = 64
    static let noiseFloorRMS: Float = 0.0004
    static let streamTimeout: CFTimeInterval = 0.35

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
        fifo.reserveCapacity(fifo.count + samples.count)
        for s in samples { fifo.append(Float(s) / 32768) }
        let cap = Int(Self.maxFifoSeconds * rate)
        if fifo.count > cap { fifo.removeFirst(fifo.count - cap) }
        lastArrival = now
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
        let stale = now - lastArrival > Self.streamTimeout
        let streamLive = !stale && lastArrival > 0
        if wasStreamLive && !streamLive {
            fifo.removeAll(keepingCapacity: true)
            softenShapingState()
        }
        wasStreamLive = streamLive
        let frameSamples = max(1, Int((r * dt).rounded()))
        let primeTarget = max(frameSamples * 2, Int(Self.primeFrameCount * r / 60))
        let holdTarget = primeTarget + max(0, latency) * Int(r) / 1000
        var due = frameSamples
        if latency < 0 {
            let boost = min(frameSamples, max(0, -latency) * Int(r) / 1000 / 8)
            due += boost
        }
        var chunk: [Float] = []
        var feedState: ProjectMAudioFeedState = .fallback

        switch micSource {
        case .off:
            feedState = .none
        case .phone:
            if !streamLive {
                feedState = .fallback
            } else if fifo.count < primeTarget {
                feedState = .idle
            } else {
                feedState = .phonePCM
                let excess = fifo.count - holdTarget
                if excess > frameSamples * 2 {
                    due += min(excess / 4, frameSamples * 2)
                }
                let take = min(due, fifo.count)
                chunk = Array(fifo.prefix(take))
                fifo.removeFirst(take)
            }
        case .continuity:
            if !streamLive {
                feedState = .fallback
            } else if fifo.count < primeTarget {
                feedState = .idle
            } else {
                feedState = .continuityPCM
                let take = min(due, fifo.count)
                chunk = Array(fifo.prefix(take))
                fifo.removeFirst(take)
            }
        }
        let fifoCount = fifo.count
        lock.unlock()

        var out: [Float]
        switch feedState {
        case .phonePCM, .continuityPCM:
            if chunk.isEmpty {
                out = [Float](repeating: 0, count: due)
            } else {
                out = shape(chunk, dt: dt, rate: r, sensitivity: sens)
                if out.count < due {
                    out.append(contentsOf: [Float](repeating: 0, count: due - out.count))
                }
            }
        case .none, .idle, .fallback:
            out = [Float](repeating: 0, count: due)
            decayShapingState(dt: dt)
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
            streamLive: streamLive,
            accentOnset: accentEnvelope,
            feedState: feedState,
            micSource: micSource
        )
        lock.unlock()
    }

    private func softenShapingState() {
        meanSquare *= 0.2
        fastEnv *= 0.2
        slowEnv *= 0.2
        accentEnvelope = 0
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
