import Foundation
import QuartzCore

/// Scene punch envelope fed into libprojectM (PCM / sensitivity), not a UIView transform.
struct BeatPunchFrame: Equatable {
    /// 0…1 kick envelope (Siła bitu × onset); drives tsunami compositor + optional PCM kick.
    var sceneEnvelope: Float
    /// Seconds since the last kick trigger (for outward wave phase).
    var kickAgeSeconds: Float
    /// True for one frame when a punch was triggered (syncs BEAT TEST dot).
    var flash: Bool
}

/// Detects kicks from `MicDrive.onset` (same path as the TV mic receiver) and animates punch envelope.
final class BeatPunchState {
    /// Instant attack (~1 GL frame), exponential release ~200 ms.
    static let attackSeconds: Float = 1.0 / 60.0
    static let releaseTau: Float = MicTuning.kickWaveReleaseTau
    static let refractorySeconds: Float = 0.12
    static let onsetTriggerThreshold: Float = 0.34
    static let onsetRearmThreshold: Float = 0.16

    private var kickArmed = true
    private var lastTrigger: CFTimeInterval = 0
    private var triggerPeak: Float = 0
    private var envelope: Float = 0
    private var recentTriggers: [CFTimeInterval] = []
    private(set) var strengthPercent: Int = MicTuning.loadTVBeatStrength()

    func setStrengthPercent(_ percent: Int) {
        strengthPercent = MicTuning.clampBeatStrength(percent)
    }

    func advance(drive: MicDrive, dt: Float, now: CFTimeInterval) -> BeatPunchFrame {
        let dtSafe = min(max(dt, 0), 0.1)
        let onset = drive.onset
        let strength = Float(strengthPercent) / 100
        var flash = false

        if strength > 0, kickArmed, onset > Self.onsetTriggerThreshold {
            let since = now - lastTrigger
            if since >= Double(Self.refractorySeconds) {
                let magnitude = min(max(onset / 2.0, 0), 1)
                triggerPeak = magnitude * strength
                if triggerPeak > 0.04 {
                    lastTrigger = now
                    kickArmed = false
                    recordTrigger(now)
                    flash = true
                }
            }
        }
        if onset < Self.onsetRearmThreshold {
            kickArmed = true
        }

        let age = Float(now - lastTrigger)
        var kickAge: Float = 0
        if age >= 0, triggerPeak > 0 {
            kickAge = age
            if age <= Self.attackSeconds {
                envelope = triggerPeak
            } else {
                let release = age - Self.attackSeconds
                envelope = triggerPeak * expf(-release / Self.releaseTau)
                if envelope < 0.008 {
                    envelope = 0
                    triggerPeak = 0
                    kickAge = 0
                }
            }
        } else {
            envelope *= expf(-dtSafe / Self.releaseTau)
            if envelope < 0.008 { envelope = 0 }
        }

        return BeatPunchFrame(sceneEnvelope: envelope, kickAgeSeconds: kickAge, flash: flash)
    }

    var punchesPerMinute: Int {
        let now = CACurrentMediaTime()
        pruneTriggers(now: now)
        guard recentTriggers.count >= 2 else { return recentTriggers.isEmpty ? 0 : 60 }
        let span = now - recentTriggers[0]
        guard span > 0.25 else { return 0 }
        return Int((Double(recentTriggers.count - 1) / span * 60).rounded())
    }

    /// Rolling rate from punch triggers (same window as `punchesPerMinute`).
    var beatsPerSecond: Float {
        let bpm = Float(punchesPerMinute)
        guard bpm > 0 else { return 0 }
        return bpm / 60
    }

    private func recordTrigger(_ now: CFTimeInterval) {
        recentTriggers.append(now)
        pruneTriggers(now: now)
    }

    private func pruneTriggers(now: CFTimeInterval) {
        let cutoff = now - 45
        if let first = recentTriggers.firstIndex(where: { $0 >= cutoff }) {
            if first > 0 { recentTriggers.removeFirst(first) }
        } else {
            recentTriggers.removeAll()
        }
    }
}
