import Combine
import Foundation

/// Which picture is showing, and the small title card in the corner.
@MainActor
final class VisualSession: ObservableObject {
    let projectMState = ProjectMRenderState()
    let audioHub = ProjectMAudioHub()
    let beatClock: BeatClock
    let micReceiver: MicReceiver

    init(beatClock: BeatClock) {
        self.beatClock = beatClock
        micReceiver = MicReceiver()
        beatClock.setVisualLatency(ms: MicTuning.loadLatency())
        projectMState.setBeatSensitivity(MicTuning.loadSensitivity())
        projectMState.setAutoCycle(MicTuning.loadAutoCycle(), seconds: MicTuning.loadCycleSeconds())
    }

    @Published private(set) var presetIndex = 0
    @Published private(set) var overlayVisible = false
    @Published private(set) var overlayPinned = false
    @Published private(set) var showHint = true
    @Published private(set) var micLive = false
    @Published private(set) var micName = ""
    @Published private(set) var showAudioDebug = false
    @Published private(set) var audioDebugDrive = MicDrive.silent
    @Published private(set) var audioDebugMetrics = ProjectMAudioHub.Metrics(
        fifoSamples: 0, fifoMs: 0, lastChunk: 0, rms: 0, agcGain: 6,
        streamLive: false, accentOnset: 0, feedState: .fallback, micSource: .phone,
        pcmPacketsPerSec: 0, gapAvgMs: 0, gapMaxMs: 0, underrunTotal: 0, pcmInRms: 0
    )
    @Published var micSource = MicTuning.loadSource()
    @Published var sensitivity = MicTuning.loadSensitivity()
    @Published var latencyMs = MicTuning.loadLatency()
    @Published var autoCycle = MicTuning.loadAutoCycle()
    @Published var cycleSeconds = MicTuning.loadCycleSeconds()
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

    var currentPresetName: String {
        MilkPresetCatalog.preset(at: presetIndex)?.displayName ?? "Preset"
    }

    func start() {
        projectMState.setTarget(presetIndex)
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
                    self.audioHub.setLatency(ms)
                    self.projectMState.setBeatSensitivity(sens)
                    self.audioHub.setBeatSensitivity(sens)
                }
            }
            micReceiver.onPCM = { [weak self] rate, samples in
                self?.audioHub.enqueue(sampleRate: rate, samples: samples)
            }
            micReceiver.onDebugOverlay = { [weak self] show in
                Task { @MainActor in
                    self?.showAudioDebug = show
                }
            }
            micReceiver.onAdoptPhoneSource = { [weak self] in
                Task { @MainActor in
                    self?.micSource = .phone
                }
            }
            micReceiver.onCycle = { [weak self] auto, seconds in
                Task { @MainActor in
                    guard let self else { return }
                    self.autoCycle = auto
                    self.cycleSeconds = seconds
                    self.projectMState.setAutoCycle(auto, seconds: seconds)
                    if auto && !self.phoneLocked { self.armCycle() }
                }
            }
            micReceiver.setShown(index: presetIndex, cycling: true)
            micReceiver.start()
            if micSource == .continuity {
                startContinuity()
            }
        }
    }

    func noteAudioFrame(drive: MicDrive, metrics: ProjectMAudioHub.Metrics) {
        guard showAudioDebug else { return }
        audioDebugDrive = drive
        audioDebugMetrics = metrics
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
        projectMState.setBeatSensitivity(clamped)
        audioHub.setBeatSensitivity(clamped)
    }

    func setLatency(_ ms: Int) {
        let clamped = MicTuning.clampLatency(ms)
        latencyMs = clamped
        micReceiver.setLatency(clamped)
        audioHub.setLatency(clamped)
        beatClock.setVisualLatency(ms: clamped)
    }

    func setAutoCycle(_ enabled: Bool) {
        autoCycle = enabled
        MicTuning.saveAutoCycle(enabled)
        projectMState.setAutoCycle(enabled, seconds: cycleSeconds)
        if enabled && !phoneLocked { armCycle() } else { cycleToken = UUID() }
    }

    func setCycleSeconds(_ seconds: Int) {
        let clamped = MicTuning.clampCycleSeconds(seconds)
        cycleSeconds = clamped
        MicTuning.saveCycleSeconds(clamped)
        projectMState.setAutoCycle(autoCycle, seconds: clamped)
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
            created.onPCM = { [weak self] samples, rate in
                Task { @MainActor in
                    guard let self, self.micSource == .continuity else { return }
                    self.audioHub.enqueue(sampleRate: rate, samples: samples)
                }
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

    private func applyPhoneChoice(_ choice: Int) {
        if choice < 0 || choice == Int(PresetWire.auto) {
            phoneLocked = false
            micReceiver.setShown(index: presetIndex, cycling: true)
            projectMState.setAutoCycle(true, seconds: cycleSeconds)
            revealOverlay()
            armCycle()
            return
        }
        guard MilkPresetCatalog.presets.indices.contains(choice) else { return }
        phoneLocked = true
        cycleToken = UUID()
        if presetIndex != choice {
            presetIndex = choice
            projectMState.setTarget(choice)
            dismissHint()
        }
        revealOverlay()
        micReceiver.setShown(index: choice, cycling: false)
    }

    func next() { step(1) }
    func previous() { step(-1) }
    func advance() { step(1) }

    func togglePin() {
        let now = Date()
        guard now.timeIntervalSince(lastSwitch) > 0.18 else { return }
        lastSwitch = now
        overlayPinned.toggle()
        overlayVisible = overlayPinned ? true : overlayVisible
        if !overlayPinned { scheduleHide() }
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
        let index = MilkPresetCatalog.index(after: presetIndex, step: delta)
        guard MilkPresetCatalog.presets.indices.contains(index) else { return }
        presetIndex = index
        projectMState.setTarget(index)
        revealOverlay()
        dismissHint()
        if phoneLocked {
            micReceiver.setShown(index: index, cycling: false)
        } else {
            micReceiver.setShown(index: index, cycling: true)
            armCycle()
        }
    }

    private func armCycle() {
        guard !phoneLocked, autoCycle else { return }
        cycleToken = UUID()
        let token = cycleToken
        let index = presetIndex
        let hold = Double(cycleSeconds)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            await self?.advanceCycle(token: token, from: index)
        }
    }

    private func advanceCycle(token: UUID, from index: Int) {
        guard !phoneLocked, autoCycle else { return }
        guard token == cycleToken, presetIndex == index else { return }
        let next = MilkPresetCatalog.randomIndex(excluding: index)
        presetIndex = next
        projectMState.setTarget(next)
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

    private func hideIfNeeded(_ token: UUID) async {
        guard token == hideToken, !overlayPinned else { return }
        overlayVisible = false
    }

    private func scheduleHintHide() {
        hintToken = UUID()
        let token = hintToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            await self?.dismissHintIfNeeded(token)
        }
    }

    private func dismissHintIfNeeded(_ token: UUID) async {
        guard token == hintToken else { return }
        showHint = false
    }

    func dismissHint() {
        showHint = false
    }
}
