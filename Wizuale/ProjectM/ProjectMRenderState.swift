import Foundation

struct ProjectMSnapshot: Sendable {
    var targetIndex: Int
    var paused: Bool
    var beatSensitivity: Float
    var autoCycle: Bool
    var cycleSeconds: Int
}

/// Handoff between SwiftUI session and the OpenGL draw loop.
final class ProjectMRenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var targetIndex = 0
    private var paused = false
    private var beatSensitivity = MicTuning.sensitivityDefault
    private var autoCycle = true
    private var cycleSeconds = MicTuning.cycleSecondsDefault

    func snapshot() -> ProjectMSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ProjectMSnapshot(
            targetIndex: targetIndex,
            paused: paused,
            beatSensitivity: beatSensitivity,
            autoCycle: autoCycle,
            cycleSeconds: cycleSeconds
        )
    }

    func setTarget(_ index: Int) {
        lock.lock()
        targetIndex = index
        lock.unlock()
    }

    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }

    func setBeatSensitivity(_ value: Float) {
        lock.lock()
        beatSensitivity = MicTuning.clampSensitivity(value)
        lock.unlock()
    }

    func setAutoCycle(_ enabled: Bool, seconds: Int) {
        lock.lock()
        autoCycle = enabled
        cycleSeconds = MicTuning.clampCycleSeconds(seconds)
        lock.unlock()
    }
}
