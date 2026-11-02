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
    /// Peak envelope scale from the last real or synthetic trigger (DEBUG).
    var lastKickPeak: Float
}

/// Detects kicks from `MicDrive.onset` (same path as the TV mic receiver) and animates punch envelope.
final class BeatPunchState {
    /// Instant attack (~1 GL frame), exponential release ~200 ms.
    static let attackSeconds: Float = 1.0 / 60.0
    static let releaseTau: Float = MicTuning.kickWaveReleaseTau
    static let refractorySeconds: Float = 0.12
    static let syntheticKickInterval: CFTimeInterval = 0.5

    private var kickArmed = true
    private var lastTrigger: CFTimeInterval = 0
    private var triggerPeak: Float = 0
    private var envelope: Float = 0
    private var recentTriggers: [CFTimeInterval] = []
    private(set) var strengthPercent: Int = MicTuning.loadTVBeatStrength()
    private(set) var lastKickPeak: Float = 0
    private(set) var lastDetectionThreshold: Float = MicTuning.kickOnsetTriggerThreshold(
        sensitivity: MicTuning.loadSensitivity()
    )

    private var lastSyntheticKick: CFTimeInterval = 0
    private var syntheticKickEnabled = false

    func setStrengthPercent(_ percent: Int) {
        strengthPercent = MicTuning.clampBeatStrength(percent)
    }

    /// When test mode turns off, drop the 500 ms metronome state (no orphan triggers).
    func setSyntheticKickEnabled(_ enabled: Bool) {
        guard syntheticKickEnabled != enabled else { return }
        syntheticKickEnabled = enabled
        if !enabled {
            lastSyntheticKick = 0
        }
    }

    /// DEBUG: irregular full-strength kick every 500 ms when **Testowy kick** is on (not AUDIO DEBUG).
    func injectSyntheticKickIfDue(now: CFTimeInterval) -> Bool {
        guard syntheticKickEnabled else { return false }
        guard now - lastSyntheticKick >= Self.syntheticKickInterval else { return false }
        lastSyntheticKick = now
        let strength = Float(strengthPercent) / 100
        guard strength > 0 else { return false }
        triggerPeak = strength
        lastKickPeak = strength
        lastTrigger = now
        kickArmed = false
        recordTrigger(now)
        return true
    }

    func advance(
        drive: MicDrive,
        dt: Float,
        now: CFTimeInterval,
        beatSensitivity: Float
    ) -> BeatPunchFrame {
        let dtSafe = min(max(dt, 0), 0.1)
        let onset = drive.onset
        let strength = Float(strengthPercent) / 100
        let threshold = MicTuning.kickOnsetTriggerThreshold(sensitivity: beatSensitivity)
        let rearm = MicTuning.kickOnsetRearmThreshold(sensitivity: beatSensitivity)
        lastDetectionThreshold = threshold
        var flash = false

        if injectSyntheticKickIfDue(now: now) {
            flash = true
        }

        let roomLive = drive.presence > 0.1 || drive.loudness > 0.07
        if strength > 0, kickArmed, roomLive, onset > threshold {
            let since = now - lastTrigger
            if since >= Double(Self.refractorySeconds) {
                let magnitude = MicTuning.kickPeakMagnitude(
                    onset: onset,
                    threshold: threshold,
                    bass: drive.bass
                )
                triggerPeak = magnitude * strength
                if triggerPeak > 0.04 {
                    lastKickPeak = triggerPeak
                    lastTrigger = now
                    kickArmed = false
                    recordTrigger(now)
                    flash = true
                }
            }
        }
        if onset < rearm {
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

        return BeatPunchFrame(
            sceneEnvelope: envelope,
            kickAgeSeconds: kickAge,
            flash: flash,
            lastKickPeak: lastKickPeak
        )
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
