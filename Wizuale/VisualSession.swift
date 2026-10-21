import Combine
import Foundation

/// What the renderer is allowed to read. The draw loop is not on the main actor,
/// so every field here is copied out under a lock.
struct RenderSnapshot: Sendable {
    var targetIndex: Int
    var album: AlbumColors?
    var wantsAlbum: Bool
    var paused: Bool
}

/// Handoff between the SwiftUI session and the Metal draw loop.
final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var targetIndex = 0
    private var album: AlbumColors?
    private var wantsAlbum = false
    private var paused = false

    func snapshot() -> RenderSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return RenderSnapshot(
            targetIndex: targetIndex,
            album: album,
            wantsAlbum: wantsAlbum,
            paused: paused
        )
    }

    func setTarget(_ index: Int) {
        lock.lock()
        targetIndex = index
        lock.unlock()
    }

    func setAlbum(_ colors: AlbumColors?) {
        lock.lock()
        album = colors
        wantsAlbum = colors != nil
        lock.unlock()
    }

    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }
}

/// Which picture is showing, and the small title card in the corner.
@MainActor
final class VisualSession: ObservableObject {
    let renderState = RenderState()

    @Published private(set) var presetIndex = 0
    @Published private(set) var overlayVisible = false
    @Published private(set) var overlayPinned = false
    @Published private(set) var showHint = true

    private var lastSwitch = Date.distantPast
    private var cycleToken = UUID()
    private var hideToken = UUID()
    private var hintToken = UUID()

    var currentPreset: Preset {
        PresetLibrary.all[presetIndex]
    }

    func start() {
        renderState.setTarget(presetIndex)
        revealOverlay()
        armCycle()
        scheduleHintHide()
    }

    func next() {
        step(1)
    }

    func previous() {
        step(-1)
    }

    /// Click moves forward through every picture, including the quieter ones.
    func advance() {
        step(1)
    }

    func togglePin() {
        let now = Date()
        guard now.timeIntervalSince(lastSwitch) > 0.18 else { return }
        lastSwitch = now
        overlayPinned.toggle()
        if overlayPinned {
            overlayVisible = true
        } else {
            scheduleHide()
        }
        dismissHint()
    }

    func revealOverlay() {
        overlayVisible = true
        scheduleHide()
    }

    private func step(_ delta: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastSwitch) > 0.18 else { return }
        lastSwitch = now
        let index = PresetLibrary.index(after: presetIndex, step: delta)
        guard PresetLibrary.all.indices.contains(index) else { return }
        presetIndex = index
        renderState.setTarget(index)
        revealOverlay()
        dismissHint()
        armCycle()
    }

    /// MilkDrop pictures change on their own. Aurora and the other quiet ones wait.
    private func armCycle() {
        cycleToken = UUID()
        let token = cycleToken
        let index = presetIndex
        guard PresetLibrary.all.indices.contains(index),
              PresetLibrary.all[index].cyclesAutomatically else { return }
        let hold = UInt64(PresetLibrary.cycleHold * 1_000_000_000)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: hold)
            await self?.advanceCycle(token: token, from: index)
        }
    }

    private func advanceCycle(token: UUID, from index: Int) {
        guard token == cycleToken, presetIndex == index else { return }
        guard let next = PresetLibrary.nextCyclingIndex(after: index) else { return }
        presetIndex = next
        renderState.setTarget(next)
        revealOverlay()
        armCycle()
    }

    private func scheduleHide() {
        hideToken = UUID()
        let token = hideToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            await self?.hideIfNeeded(token)
        }
    }

    private func hideIfNeeded(_ token: UUID) {
        guard token == hideToken, !overlayPinned else { return }
        overlayVisible = false
    }

    private func scheduleHintHide() {
        hintToken = UUID()
        let token = hintToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self?.hideHint(token)
        }
    }

    private func hideHint(_ token: UUID) {
        guard token == hintToken else { return }
        showHint = false
    }

    private func dismissHint() {
        showHint = false
        hintToken = UUID()
    }
}
