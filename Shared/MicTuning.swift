import Foundation

/// Which microphone drives the picture. The phone app is the Wi-Fi companion.
/// Continuity uses the Apple TV's own session. Off leaves the beat clock alone.
enum MicInputSource: Int, CaseIterable, Identifiable, Sendable {
    case phone = 0
    case continuity = 1
    case off = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .phone: return "iPhone app (Wi-Fi)"
        case .continuity: return "Continuity mic"
        case .off: return "Off"
        }
    }
}

/// Saved on each device. The phone sends both numbers on the control channel.
enum MicTuning {
    static let sensitivityKey = "wizuale.mic.sensitivity"
    static let latencyKey = "wizuale.mic.latencyMs"
    static let sourceKey = "wizuale.mic.source"
    static let autoCycleKey = "wizuale.mic.autoCycle"
    static let cycleSecondsKey = "wizuale.mic.cycleSeconds"
    static let tvAudioDebugKey = "wizuale.mic.tvAudioDebug"
    static let testSyntheticKickKey = "wizuale.mic.testSyntheticKick"
    static let tvTestSyntheticKickKey = "wizuale.tv.testSyntheticKick"
    static let pictureBrightnessKey = "wizuale.mic.pictureBrightness"
    static let tvPictureBrightnessKey = "wizuale.tv.pictureBrightness"
    static let beatStrengthKey = "wizuale.mic.beatStrength"
    static let tvBeatStrengthKey = "wizuale.tv.beatStrength"
    static let sceneIntensityKey = "wizuale.mic.sceneIntensity"
    static let tvSceneIntensityKey = "wizuale.tv.sceneIntensity"
    static let wholeMixGainKey = "wizuale.mic.gain.wholeMix"
    static let midGainKey = "wizuale.mic.gain.mid"
    static let topGainKey = "wizuale.mic.gain.top"
    static let kickGainKey = "wizuale.mic.gain.kick"
    static let percussionGainKey = "wizuale.mic.gain.percussion"

    static let bandGainMin = 0
    static let bandGainMax = 100
    static let wholeMixGainDefault = 60
    static let midGainDefault = 50
    static let topGainDefault = 50
    static let kickGainDefault = 60
    static let percussionGainDefault = 50

    /// EMA time constant for quiet-room lift on continuous projectM boost (TV).
    static let adaptiveBassMeanSeconds: Float = 4.0

    static let pictureBrightnessMin = 10
    static let pictureBrightnessMax = 100
    static let pictureBrightnessDefault = 100

    static let beatStrengthMin = 0
    static let beatStrengthMax = 100
    static let beatStrengthDefault = 85

    /// Permille of f301047 scene-modulation baseline: 100 = 1×, 2000 = 20× (default), 4000 = 40× max.
    static let sceneIntensityMinPermille = 0
    static let sceneIntensityMaxPermille = 4000
    static let sceneIntensityDefaultPermille = 2000

    /// Short kick accent @ 1× Intensywność and 100% Siła bitu (on top of continuous bass).
    static let scenePunchPCMSMixBaseline: Float = 0.16
    static let scenePunchSensitivityBoostBaseline: Float = 0.20
    /// Continuous room bass → `projectm_set_beat_sensitivity` (dominant “boom boom”; Intensywność).
    static let sceneContinuousSensitivityBaseline: Float = 0.88
    /// Tanh ceiling for kick-only sensitivity accent (keeps bass headroom when kick fires).
    static let sceneKickAccentSensitivityCeiling: Float = 2.4

    /// Radial tsunami compositor (UV displacement, brightness-neutral).
    static let kickWaveReleaseTau: Float = 0.095
    static let kickWaveRingFrequency: Float = 18
    static let kickWavePhaseSpeed: Float = 18
    /// Radial falloff in compositor shader (`exp(-r * falloff)`).
    static let kickWaveRingFalloff: Float = 0.85
    /// Max outward UV shift at envelope=1, Siła bitu=100% — smaller than continuous preset motion.
    static let kickWaveMaxDisplacement: Float = 0.058
    /// Caps `projectm_set_beat_sensitivity` during a punch so presets stay stable at max slider.
    static let sceneBeatSensitivityCeiling: Float = 10

    static let sensitivityMin: Float = 0.25
    static let sensitivityMax: Float = 3
    static let sensitivityDefault: Float = 1
    static let latencyMin = -200
    static let latencyMax = 400
    static let latencyStep = 10
    static let cycleSecondsMin = 15
    static let cycleSecondsMax = 600
    static let cycleSecondsDefault = 45

    static func clampSensitivity(_ value: Float) -> Float {
        guard value.isFinite else { return sensitivityDefault }
        return min(max(value, sensitivityMin), sensitivityMax)
    }

    static func loadSensitivity() -> Float {
        guard UserDefaults.standard.object(forKey: sensitivityKey) != nil else {
            return sensitivityDefault
        }
        return clampSensitivity(UserDefaults.standard.float(forKey: sensitivityKey))
    }

    static func saveSensitivity(_ value: Float) {
        UserDefaults.standard.set(clampSensitivity(value), forKey: sensitivityKey)
    }

    static func clampLatency(_ ms: Int) -> Int {
        let stepped = Int((Double(ms) / Double(latencyStep)).rounded()) * latencyStep
        return min(max(stepped, latencyMin), latencyMax)
    }

    static func loadLatency() -> Int {
        guard UserDefaults.standard.object(forKey: latencyKey) != nil else { return 0 }
        return clampLatency(UserDefaults.standard.integer(forKey: latencyKey))
    }

    static func saveLatency(_ ms: Int) {
        UserDefaults.standard.set(clampLatency(ms), forKey: latencyKey)
    }

    static func loadSource() -> MicInputSource {
        let raw = UserDefaults.standard.integer(forKey: sourceKey)
        return MicInputSource(rawValue: raw) ?? .phone
    }

    static func saveSource(_ source: MicInputSource) {
        UserDefaults.standard.set(source.rawValue, forKey: sourceKey)
    }

    static func clampCycleSeconds(_ seconds: Int) -> Int {
        min(max(seconds, cycleSecondsMin), cycleSecondsMax)
    }

    static func loadAutoCycle() -> Bool {
        guard UserDefaults.standard.object(forKey: autoCycleKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: autoCycleKey)
    }

    static func saveAutoCycle(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoCycleKey)
    }

    static func loadCycleSeconds() -> Int {
        guard UserDefaults.standard.object(forKey: cycleSecondsKey) != nil else {
            return cycleSecondsDefault
        }
        return clampCycleSeconds(UserDefaults.standard.integer(forKey: cycleSecondsKey))
    }

    static func saveCycleSeconds(_ seconds: Int) {
        UserDefaults.standard.set(clampCycleSeconds(seconds), forKey: cycleSecondsKey)
    }

    static func loadTVAudioDebug() -> Bool {
        UserDefaults.standard.bool(forKey: tvAudioDebugKey)
    }

    static func saveTVAudioDebug(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: tvAudioDebugKey)
    }

    static func loadTestSyntheticKick() -> Bool {
        UserDefaults.standard.bool(forKey: testSyntheticKickKey)
    }

    static func saveTestSyntheticKick(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: testSyntheticKickKey)
    }

    static func loadTVTestSyntheticKick() -> Bool {
        UserDefaults.standard.bool(forKey: tvTestSyntheticKickKey)
    }

    static func saveTVTestSyntheticKick(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: tvTestSyntheticKickKey)
    }

    /// Maps phone **Sensitivity** (0.25…3) to kick onset gate on TV — not scene Intensywność.
    static func kickOnsetTriggerThreshold(sensitivity: Float) -> Float {
        let s = clampSensitivity(sensitivity)
        let span = sensitivityMax - sensitivityMin
        let norm = span > 0 ? (s - sensitivityMin) / span : 0.5
        let high: Float = 0.44
        let low: Float = 0.13
        return high - norm * (high - low)
    }

    static func kickOnsetRearmThreshold(sensitivity: Float) -> Float {
        kickOnsetTriggerThreshold(sensitivity: sensitivity) * 0.48
    }

    /// Proportional tsunami / PCM kick from onset above gate and 40–120 Hz bass energy.
    static func kickPeakMagnitude(onset: Float, threshold: Float, bass: Float) -> Float {
        let excess = min(max(onset - threshold, 0), 1.35)
        guard excess > 0.02 else { return 0 }
        let bassW = min(max(bass, 0), 1.6)
        let bassMix = 0.42 + 0.58 * min(bassW, 1)
        return min(1, excess * bassMix)
    }

    static func clampPictureBrightness(_ percent: Int) -> Int {
        min(max(percent, pictureBrightnessMin), pictureBrightnessMax)
    }

    static func loadPictureBrightness() -> Int {
        guard UserDefaults.standard.object(forKey: pictureBrightnessKey) != nil else {
            return pictureBrightnessDefault
        }
        return clampPictureBrightness(UserDefaults.standard.integer(forKey: pictureBrightnessKey))
    }

    static func savePictureBrightness(_ percent: Int) {
        UserDefaults.standard.set(clampPictureBrightness(percent), forKey: pictureBrightnessKey)
    }

    static func loadTVPictureBrightness() -> Int {
        guard UserDefaults.standard.object(forKey: tvPictureBrightnessKey) != nil else {
            return pictureBrightnessDefault
        }
        return clampPictureBrightness(UserDefaults.standard.integer(forKey: tvPictureBrightnessKey))
    }

    static func saveTVPictureBrightness(_ percent: Int) {
        UserDefaults.standard.set(clampPictureBrightness(percent), forKey: tvPictureBrightnessKey)
    }

    static func clampBeatStrength(_ percent: Int) -> Int {
        min(max(percent, beatStrengthMin), beatStrengthMax)
    }

    static func loadBeatStrength() -> Int {
        guard UserDefaults.standard.object(forKey: beatStrengthKey) != nil else {
            return beatStrengthDefault
        }
        return clampBeatStrength(UserDefaults.standard.integer(forKey: beatStrengthKey))
    }

    static func saveBeatStrength(_ percent: Int) {
        UserDefaults.standard.set(clampBeatStrength(percent), forKey: beatStrengthKey)
    }

    static func loadTVBeatStrength() -> Int {
        guard UserDefaults.standard.object(forKey: tvBeatStrengthKey) != nil else {
            return beatStrengthDefault
        }
        return clampBeatStrength(UserDefaults.standard.integer(forKey: tvBeatStrengthKey))
    }

    static func saveTVBeatStrength(_ percent: Int) {
        UserDefaults.standard.set(clampBeatStrength(percent), forKey: tvBeatStrengthKey)
    }

    static func clampSceneIntensity(_ permille: Int) -> Int {
        min(max(permille, sceneIntensityMinPermille), sceneIntensityMaxPermille)
    }

    /// Multiplier vs f301047 scene path (100 permille → 1.0).
    static func sceneIntensityMultiplier(_ permille: Int) -> Float {
        Float(clampSceneIntensity(permille)) / 100
    }

    static func loadSceneIntensity() -> Int {
        guard UserDefaults.standard.object(forKey: sceneIntensityKey) != nil else {
            return sceneIntensityDefaultPermille
        }
        return clampSceneIntensity(UserDefaults.standard.integer(forKey: sceneIntensityKey))
    }

    static func saveSceneIntensity(_ permille: Int) {
        UserDefaults.standard.set(clampSceneIntensity(permille), forKey: sceneIntensityKey)
    }

    static func loadTVSceneIntensity() -> Int {
        guard UserDefaults.standard.object(forKey: tvSceneIntensityKey) != nil else {
            return sceneIntensityDefaultPermille
        }
        return clampSceneIntensity(UserDefaults.standard.integer(forKey: tvSceneIntensityKey))
    }

    static func saveTVSceneIntensity(_ permille: Int) {
        UserDefaults.standard.set(clampSceneIntensity(permille), forKey: tvSceneIntensityKey)
    }

    static func formatSceneIntensity(_ permille: Int) -> String {
        let mul = Double(clampSceneIntensity(permille)) / 100
        if abs(mul - mul.rounded()) < 0.05 {
            return "\(Int(mul.rounded()))×"
        }
        return String(format: "%.1f×", mul)
    }

    /// Tanh soft ceiling — keeps motion at high intensity without a hard clip knee.
    static func sceneSoftSaturate(_ value: Float, at ceiling: Float = sceneBeatSensitivityCeiling) -> Float {
        guard value.isFinite, ceiling > 0 else { return sensitivityDefault }
        if value <= 0 { return clampSensitivity(value) }
        return ceiling * tanhf(value / ceiling)
    }

    /// libprojectM beat sensitivity during scene modulation (user slider stays 0.25…3 in UI state).
    static func clampProjectMBeatSensitivity(_ value: Float) -> Float {
        guard value.isFinite else { return sensitivityDefault }
        return min(max(value, sensitivityMin), sceneBeatSensitivityCeiling)
    }

    /// Sum base slider + saturated continuous bass boost + smaller saturated kick accent.
    static func clampSceneBeatSensitivity(
        base: Float,
        kickBoost: Float,
        continuousBoost: Float
    ) -> Float {
        let baseClamped = clampSensitivity(base)
        let cont = continuousBoost.isFinite ? max(0, continuousBoost) : 0
        let kick = kickBoost.isFinite ? max(0, kickBoost) : 0
        let combined = baseClamped
            + sceneSoftSaturate(cont, at: sceneBeatSensitivityCeiling)
            + sceneSoftSaturate(kick, at: sceneKickAccentSensitivityCeiling)
        return clampProjectMBeatSensitivity(combined)
    }

    /// `uMaxDisp` uniform: Siła bitu × peak UV (envelope applied once in the shader).
    static func kickWaveShaderMaxDisplacement(strengthScale: Float) -> Float {
        min(max(strengthScale, 0), 1) * kickWaveMaxDisplacement
    }

    /// Peak outward UV shift at this envelope (for DEBUG readout).
    static func kickWaveEffectiveDisplacement(envelope: Float, strengthScale: Float) -> Float {
        let env = min(max(envelope, 0), 1.4)
        return env * kickWaveShaderMaxDisplacement(strengthScale: strengthScale)
    }

    /// PCM after scene punch — tanh limiter (avoids blowout / NaN-ish whites).
    static func scenePCMSoftLimit(_ sample: Float, peak: Float = 0.78) -> Float {
        guard sample.isFinite, peak > 0 else { return 0 }
        return peak * tanhf(sample / peak)
    }

    /// Phone tap before analysis — prevents AGC/normalizer from pinning on clip bursts.
    static func captureTapSoftLimit(_ sample: Float, peak: Float = 0.92) -> Float {
        guard sample.isFinite, peak > 0 else { return 0 }
        return peak * tanhf(sample / peak)
    }

    static func clampBandGainPercent(_ percent: Int) -> Int {
        min(max(percent, bandGainMin), bandGainMax)
    }

    static func bandGainMultiplier(_ percent: Int) -> Float {
        let p = Float(clampBandGainPercent(percent))
        return 0.35 + (p / 100) * 1.05
    }

    /// Scales continuous `drive.bass` boost when long-term mean is low (quiet passages).
    static func adaptiveContinuousBassScale(liveBass: Float, slowMean: Float) -> Float {
        let live = min(max(liveBass, 0), 2.8)
        let mean = min(max(slowMean, 0), 2.8)
        guard live.isFinite, mean.isFinite else { return 1 }
        let reference = max(mean, 0.10)
        let ratio = reference / max(live, 0.06)
        return min(max(0.75 + ratio * 0.35, 0.85), 2.35)
    }
}

/// Per-band gains on the phone (0…100%). Applied before UDP features + PCM wire gain.
struct MicBandGains: Equatable, Sendable {
    var wholeMix: Int
    var mid: Int
    var top: Int
    var kick: Int
    var percussion: Int

    static let defaults = MicBandGains(
        wholeMix: MicTuning.wholeMixGainDefault,
        mid: MicTuning.midGainDefault,
        top: MicTuning.topGainDefault,
        kick: MicTuning.kickGainDefault,
        percussion: MicTuning.percussionGainDefault
    )

    static func load() -> MicBandGains {
        func pct(_ key: String, _ defaultValue: Int) -> Int {
            guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
            return MicTuning.clampBandGainPercent(UserDefaults.standard.integer(forKey: key))
        }
        return MicBandGains(
            wholeMix: pct(MicTuning.wholeMixGainKey, MicTuning.wholeMixGainDefault),
            mid: pct(MicTuning.midGainKey, MicTuning.midGainDefault),
            top: pct(MicTuning.topGainKey, MicTuning.topGainDefault),
            kick: pct(MicTuning.kickGainKey, MicTuning.kickGainDefault),
            percussion: pct(MicTuning.percussionGainKey, MicTuning.percussionGainDefault)
        )
    }

    func save() {
        UserDefaults.standard.set(MicTuning.clampBandGainPercent(wholeMix), forKey: MicTuning.wholeMixGainKey)
        UserDefaults.standard.set(MicTuning.clampBandGainPercent(mid), forKey: MicTuning.midGainKey)
        UserDefaults.standard.set(MicTuning.clampBandGainPercent(top), forKey: MicTuning.topGainKey)
        UserDefaults.standard.set(MicTuning.clampBandGainPercent(kick), forKey: MicTuning.kickGainKey)
        UserDefaults.standard.set(MicTuning.clampBandGainPercent(percussion), forKey: MicTuning.percussionGainKey)
    }

    func scale(_ features: MicFeatures) -> MicFeatures {
        let kickM = MicTuning.bandGainMultiplier(kick)
        let midM = MicTuning.bandGainMultiplier(mid)
        let topM = MicTuning.bandGainMultiplier(top)
        let percM = MicTuning.bandGainMultiplier(percussion)
        let mixM = MicTuning.bandGainMultiplier(wholeMix)
        return MicFeatures(
            bass: features.bass * kickM * mixM,
            lowMid: features.lowMid * percM * mixM,
            mid: features.mid * midM * mixM,
            high: features.high * topM * mixM,
            loudness: features.loudness * mixM,
            onset: features.onset * kickM * percM,
            flux: features.flux * percM
        )
    }

    func wireGainMultiplier() -> Float {
        MicTuning.bandGainMultiplier(wholeMix)
    }
}

/// Mean room energy, measured with the room quiet. Analysis subtracts it
/// before the auto gain, and the gain starts from this level.
struct MicNoiseFloor: Equatable, Sendable {
    var bass: Float
    var lowMid: Float
    var mid: Float
    var high: Float
    var loudness: Float

    static let zero = MicNoiseFloor(bass: 0, lowMid: 0, mid: 0, high: 0, loudness: 0)

    var isSet: Bool {
        bass > 0 || lowMid > 0 || mid > 0 || high > 0 || loudness > 0
    }
}

enum MicCalibrationStore {
    static let key = "wizuale.mic.noiseFloor"

    static func load() -> MicNoiseFloor {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let values = try? JSONDecoder().decode([Float].self, from: data),
            values.count == 5
        else { return .zero }
        return MicNoiseFloor(
            bass: sanitize(values[0]),
            lowMid: sanitize(values[1]),
            mid: sanitize(values[2]),
            high: sanitize(values[3]),
            loudness: sanitize(values[4])
        )
    }

    static func save(_ floor: MicNoiseFloor) {
        let values = [
            sanitize(floor.bass),
            sanitize(floor.lowMid),
            sanitize(floor.mid),
            sanitize(floor.high),
            sanitize(floor.loudness)
        ]
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func sanitize(_ value: Float) -> Float {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, 0.5)
    }
}
