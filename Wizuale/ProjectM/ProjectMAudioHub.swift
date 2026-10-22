import Foundation

/// Thread-safe PCM queue from the mic receiver to the GL draw loop.
final class ProjectMAudioHub: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [(rate: Float, samples: [Int16])] = []
    private var beatSensitivity: Float = MicTuning.sensitivityDefault

    func setBeatSensitivity(_ value: Float) {
        lock.lock()
        beatSensitivity = MicTuning.clampSensitivity(value)
        lock.unlock()
    }

    func enqueue(sampleRate: Float, samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        chunks.append((sampleRate, samples))
        if chunks.count > 8 { chunks.removeFirst(chunks.count - 8) }
        lock.unlock()
    }

    /// Drains queued PCM into projectM. Call only on the GL thread with a valid context.
    func feed(projectM: ProjectMController) {
        lock.lock()
        let batch = chunks
        chunks.removeAll(keepingCapacity: true)
        let gain = beatSensitivity
        lock.unlock()
        for chunk in batch {
            projectM.addPCM(samples: chunk.samples, gain: gain)
        }
    }
}
