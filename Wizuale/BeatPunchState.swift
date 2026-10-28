import CoreGraphics
import Foundation
import QuartzCore

/// Geometry-only beat punch on the projectM frame (scale + slight rotation, no brightness).
struct BeatPunchFrame: Equatable {
    var scale: CGFloat
    var rotationRadians: CGFloat
    /// True for one frame when a punch was triggered (syncs BEAT TEST dot).
    var flash: Bool
}

/// Detects kicks from `MicDrive.onset` (same path as the TV mic receiver) and animates punch envelope.
final class BeatPunchState {
    static let baseOverscan: Float = 1.03
    static let maxExtraScale: Float = 0.09
    static let attackSeconds: Float = 0.028
    static let releaseTau: Float = 0.19
    static let refractorySeconds: Float = 0.12
    static let maxRotationDegrees: Float = 1.6

    private var kickArmed = true
    private var lastTrigger: CFTimeInterval = 0
    private var triggerPeak: Float = 0
    private var envelope: Float = 0
    private var rotationSign: Float = 1
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

        if strength > 0, kickArmed, onset > 0.48 {
            let since = now - lastTrigger
            if since >= Double(Self.refractorySeconds) {
                let magnitude = min(max(onset / 2.0, 0), 1)
                triggerPeak = magnitude * strength
                if triggerPeak > 0.04 {
                    lastTrigger = now
                    kickArmed = false
                    rotationSign = Bool.random() ? 1 : -1
                    recordTrigger(now)
                    flash = true
                }
            }
        }
        if onset < 0.26 {
            kickArmed = true
        }

        let age = Float(now - lastTrigger)
        if age >= 0, triggerPeak > 0 {
            if age < Self.attackSeconds {
                let t = age / Self.attackSeconds
                let eased = t * t * (3 - 2 * t)
                envelope = triggerPeak * eased
            } else {
                let release = age - Self.attackSeconds
                let decay = expf(-release / Self.releaseTau)
                let overshoot = 1 + 0.1 * expf(-release / 0.045)
                envelope = triggerPeak * decay * overshoot
                if envelope < 0.008 {
                    envelope = 0
                    triggerPeak = 0
                }
            }
        } else {
            envelope *= expf(-dtSafe / Self.releaseTau)
            if envelope < 0.008 { envelope = 0 }
        }

        let extra = envelope * Self.maxExtraScale
        let scale = CGFloat(Self.baseOverscan + extra)
        let rot = CGFloat(envelope * Self.maxRotationDegrees * rotationSign * (Float.pi / 180))
        return BeatPunchFrame(scale: scale, rotationRadians: rot, flash: flash)
    }

    var punchesPerMinute: Int {
        let now = CACurrentMediaTime()
        pruneTriggers(now: now)
        guard recentTriggers.count >= 2 else { return recentTriggers.isEmpty ? 0 : 60 }
        let span = now - recentTriggers[0]
        guard span > 0.25 else { return 0 }
        return Int((Double(recentTriggers.count - 1) / span * 60).rounded())
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
