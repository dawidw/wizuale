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

    static let sensitivityMin: Float = 0.25
    static let sensitivityMax: Float = 3
    static let sensitivityDefault: Float = 1
    static let latencyMin = -200
    static let latencyMax = 400
    static let latencyStep = 10

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
