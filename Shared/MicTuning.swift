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
    static let pictureBrightnessKey = "wizuale.mic.pictureBrightness"
    static let tvPictureBrightnessKey = "wizuale.tv.pictureBrightness"
    static let beatStrengthKey = "wizuale.mic.beatStrength"
    static let tvBeatStrengthKey = "wizuale.tv.beatStrength"

    static let pictureBrightnessMin = 10
    static let pictureBrightnessMax = 100
    static let pictureBrightnessDefault = 100

    static let beatStrengthMin = 0
    static let beatStrengthMax = 100
    static let beatStrengthDefault = 70

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
