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
    let beatClock: BeatClock
    let micReceiver: MicReceiver

    init(beatClock: BeatClock) {
        self.beatClock = beatClock
        micReceiver = MicReceiver()
        beatClock.setVisualLatency(ms: MicTuning.loadLatency())
    }

    @Published private(set) var presetIndex = 0
    @Published private(set) var overlayVisible = false
    @Published private(set) var overlayPinned = false
    @Published private(set) var showHint = true
    @Published private(set) var micLive = false
    @Published private(set) var micName = ""
    @Published var micSource = MicTuning.loadSource()
    @Published var sensitivity = MicTuning.loadSensitivity()
    @Published var latencyMs = MicTuning.loadLatency()
    @Published var showMicSettings = false
    @Published var showContinuityPicker = false
    @Published private(set) var continuityStatus = ""

    private var micWired = false
    private var continuity: ContinuityMic?
    private var phoneLocked = false
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
        if !micWired {
            micWired = true
            micReceiver.onStatus = { [weak self] live, name in
                Task { @MainActor in
                    self?.micLive = live
                    self?.micName = name
                }
            }
            micReceiver.onCommand = { [weak self] choice in
                Task { @MainActor in
                    self?.applyPhoneChoice(choice)
                }
            }
            micReceiver.onTuning = { [weak self] ms, sens in
                Task { @MainActor in
                    guard let self else { return }
                    self.latencyMs = ms
                    self.sensitivity = sens
                    self.beatClock.setVisualLatency(ms: ms)
                }
            }
            micReceiver.setShown(index: presetIndex, cycling: true)
            micReceiver.start()
            if micSource == .continuity {
                startContinuity()
            }
        }
    }

    func openSettings() {
        showMicSettings = true
        dismissHint()
    }

    func closeSettings() {
        showMicSettings = false
    }

    func setMicSource(_ source: MicInputSource) {
        micSource = source
        micReceiver.setSource(source)
        if source == .continuity {
            startContinuity()
        } else {
            stopContinuity()
            continuityStatus = ""
        }
    }

    func setSensitivity(_ value: Float) {
        let clamped = MicTuning.clampSensitivity(value)
        sensitivity = clamped
        micReceiver.setSensitivity(clamped)
    }

    func setLatency(_ ms: Int) {
        let clamped = MicTuning.clampLatency(ms)
        latencyMs = clamped
        micReceiver.setLatency(clamped)
        beatClock.setVisualLatency(ms: clamped)
    }

    func beginContinuityPairing() {
        setMicSource(.continuity)
        showContinuityPicker = true
    }

    private func startContinuity() {
        let mic: ContinuityMic
        if let continuity {
            mic = continuity
        } else {
            let created = ContinuityMic()
            created.onFeatures = { [weak self] features in
                self?.micReceiver.ingestLocal(features)
            }
            created.onStatus = { [weak self] text in
                Task { @MainActor in
                    self?.continuityStatus = text
                }
            }
            continuity = created
            mic = created
        }
        mic.start()
    }

    private func stopContinuity() {
        continuity?.stop()
    }

    /// `-1` lets the pictures rotate again. Any other index locks that picture
    /// and cancels the phrase timer until the phone asks for auto.
    private func applyPhoneChoice(_ choice: Int) {
        if choice < 0 {
            phoneLocked = false
            micReceiver.setShown(index: presetIndex, cycling: true)
            armCycle()
            return
        }
        guard PresetLibrary.all.indices.contains(choice) else { return }
        phoneLocked = true
        cycleToken = UUID()
        if presetIndex != choice {
            presetIndex = choice
            renderState.setTarget(choice)
            revealOverlay()
            dismissHint()
        }
        micReceiver.setShown(index: choice, cycling: false)
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
        if phoneLocked {
            micReceiver.setShown(index: index, cycling: false)
        } else {
            micReceiver.setShown(index: index, cycling: true)
            armCycle()
        }
    }

    /// MilkDrop pictures change on their own. Aurora and the other quiet ones wait.
    /// With a matched tempo the change waits for the next 8-bar phrase after the hold.
    private func armCycle() {
        guard !phoneLocked else { return }
        cycleToken = UUID()
        let token = cycleToken
        let index = presetIndex
        guard PresetLibrary.all.indices.contains(index),
              PresetLibrary.all[index].cyclesAutomatically else { return }
        let started = Date()
        Task { [weak self] in
            await self?.waitForCycle(token: token, from: index, started: started)
        }
    }

    private func waitForCycle(token: UUID, from index: Int, started: Date) async {
        let earliest = started.addingTimeInterval(PresetLibrary.cycleHold)
        while token == cycleToken, presetIndex == index {
            let now = Date()
            if now < earliest {
                let nap = min(earliest.timeIntervalSince(now), 0.5)
                try? await Task.sleep(nanoseconds: sleepNanos(nap))
                continue
            }
            if let remaining = beatClock.secondsUntilPhraseBoundary(), remaining.isFinite {
                if remaining <= 0.1 { break }
                let nap = min(max(remaining - 0.04, 0.05), 1.0)
                try? await Task.sleep(nanoseconds: sleepNanos(nap))
                continue
            }
            break
        }
        advanceCycle(token: token, from: index)
    }

    private func sleepNanos(_ seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return UInt64(seconds * 1_000_000_000)
    }

    private func advanceCycle(token: UUID, from index: Int) {
        guard !phoneLocked else { return }
        guard token == cycleToken, presetIndex == index else { return }
        guard let next = PresetLibrary.nextCyclingIndex(after: index) else { return }
        presetIndex = next
        renderState.setTarget(next)
        revealOverlay()
        micReceiver.setShown(index: next, cycling: true)
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
