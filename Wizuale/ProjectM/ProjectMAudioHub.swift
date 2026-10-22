import Foundation
import QuartzCore

/// PCM queue from the mic receiver to the GL draw loop, with three jobs:
///
/// 1. Pacing. The phone's mic tap delivers ~100 ms bursts (~4800 samples). projectM
///    only analyses the newest 576 samples each frame, so dumping a burst in one frame
///    threw ~88% of the audio away and left the next ~5 frames looking at stale data.
///    Samples now play out at real time (rate × frame dt) from a small jitter buffer.
/// 2. Level. A raw iPhone mic (measurement mode) is far quieter than line-level music.
///    A slow automatic gain brings it up to a music-like RMS.
/// 3. Punch. A transient shaper (fast vs slow envelope) emphasises kick onsets so
///    projectM's bass/mid/treb (each relative to its own long average) swing harder.
///    The phone's Sensitivity slider scales this; projectm_set_beat_sensitivity is
///    stored but unused by libprojectM 4.
///
/// The Latency setting adds to the jitter buffer, so it now really delays the picture.
final class ProjectMAudioHub: @unchecked Sendable {
    private let lock = NSLock()
    private var fifo: [Float] = []
    private var rate: Float = 48_000
    private var sensitivity: Float = MicTuning.loadSensitivity()
    private var latencyMs: Int = MicTuning.loadLatency()
    private var primed = false
    private var lastArrival: CFTimeInterval = 0

    // Shaping state. Touched only by `feed`, which runs on the GL thread.
    private var lastFeed: CFTimeInterval = 0
    private var meanSquare: Float = 0
    private var agcGain: Float = 4
    private var fastEnv: Float = 0
    private var slowEnv: Float = 0

    static let baseJitterSeconds: Float = 0.12
    static let minJitterSeconds: Float = 0.03
    static let targetRMS: Float = 0.16
    static let maxGain: Float = 48
    static let noiseFloorRMS: Float = 0.0006

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
            primed = false
        }
        fifo.reserveCapacity(fifo.count + samples.count)
        for s in samples { fifo.append(Float(s) / 32768) }
        let cap = Int(rate)  // never hold more than 1 s
        if fifo.count > cap { fifo.removeFirst(fifo.count - cap) }
        lastArrival = now
        lock.unlock()
    }

    /// Hands this frame's share of audio to `sink` (mono floats in -1...1). Call once per frame.
    func feed(now: CFTimeInterval = CACurrentMediaTime(), into sink: ([Float]) -> Void) {
        let dt = Float(lastFeed > 0 ? min(max(now - lastFeed, 0), 0.1) : 1.0 / 60.0)
        lastFeed = now

        lock.lock()
        let r = rate
        let sens = sensitivity
        let jitter = max(Self.minJitterSeconds, Self.baseJitterSeconds + Float(latencyMs) / 1000)
        let target = Int(jitter * r)
        let stale = now - lastArrival > 0.3
        var due = max(1, Int((r * dt).rounded()))
        var chunk: [Float] = []
        if !primed && fifo.count >= target && !stale { primed = true }
        if primed {
            // Drift control: if bursts piled up beyond target + one burst, catch up gently.
            let excess = fifo.count - target - Int(r * 0.12)
            if excess > 0 { due += excess / 6 }
            let take = min(due, fifo.count)
            chunk = Array(fifo.prefix(take))
            fifo.removeFirst(take)
            if fifo.isEmpty { primed = false }  // underrun: rebuild the jitter buffer
        }
        lock.unlock()

        if chunk.isEmpty {
            // Stream stopped: let projectM settle on silence instead of freezing the last window.
            if stale { sink([Float](repeating: 0, count: due)) }
            return
        }
        sink(shape(chunk, dt: dt, rate: r, sensitivity: sens))
    }

    private func shape(_ input: [Float], dt: Float, rate: Float, sensitivity: Float) -> [Float] {
        let fastAttack = 1 - expf(-1 / (0.002 * rate))
        let fastRelease = 1 - expf(-1 / (0.060 * rate))
        let slowCoef = 1 - expf(-1 / (0.300 * rate))
        let rmsCoef = 1 - expf(-1 / (1.5 * rate))
        let punch = 0.9 * sensitivity
        var out = [Float](repeating: 0, count: input.count)
        let gain = agcGain
        for i in 0..<input.count {
            let x = input[i]
            let a = abs(x)
            fastEnv += (a - fastEnv) * (a > fastEnv ? fastAttack : fastRelease)
            slowEnv += (a - slowEnv) * slowCoef
            meanSquare += (x * x - meanSquare) * rmsCoef
            let ratio = slowEnv > 1e-6 ? fastEnv / slowEnv : 1
            let boost = 1 + punch * min(max(ratio - 1, 0), 3)
            out[i] = tanhf(x * gain * boost)
        }
        let rms = sqrtf(meanSquare)
        if rms > Self.noiseFloorRMS {
            let desired = min(max(Self.targetRMS / rms, 1), Self.maxGain)
            agcGain += (desired - agcGain) * (1 - expf(-dt / 0.6))
        }
        return out
    }
}
