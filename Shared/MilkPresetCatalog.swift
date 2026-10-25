import Foundation

/// Stock `.milk` presets bundled with the TV app. The Mic app reads the same
/// `manifest.json` from its copy of `Wizuale/Resources/Presets` (see `project.yml`).
struct MilkPreset: Equatable, Identifiable, Sendable, Codable {
    var id: Int
    var name: String
    /// Path relative to the `Presets` folder in the bundle (e.g. `files/foo.milk`).
    var file: String
    /// Optional thumbnail path relative to the `Presets` folder (e.g. `thumbs/foo.jpg`).
    var thumb: String?
    /// Playlist section (`MilkDrop` stock presets, then `Study of Space`).
    var group: String?

    var displayName: String { name }
}

enum MilkPresetCatalog {
    static let cycleHold: Double = 45
    static let softCutSeconds: Double = 2.0

    private static let loaded: [MilkPreset] = loadManifest()

    static var presets: [MilkPreset] { loaded }

    static var count: Int { loaded.count }

    /// Presets grouped for the Mic picker (order preserved).
    static var groupedPresets: [(group: String, presets: [MilkPreset])] {
        var order: [String] = []
        var buckets: [String: [MilkPreset]] = [:]
        for preset in loaded {
            let key = preset.group ?? "Presets"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(preset)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    static func preset(at index: Int) -> MilkPreset? {
        guard loaded.indices.contains(index) else { return nil }
        return loaded[index]
    }

    static func index(after index: Int, step: Int) -> Int {
        let n = max(loaded.count, 1)
        return (index + step + n) % n
    }

    static func randomIndex(excluding: Int? = nil) -> Int {
        guard loaded.count > 1 else { return 0 }
        var pick = Int.random(in: 0..<loaded.count)
        if let excluding, loaded.count > 1 {
            while pick == excluding { pick = Int.random(in: 0..<loaded.count) }
        }
        return pick
    }

    /// Absolute filesystem path for projectM, or nil if the bundle is incomplete.
    static func absolutePath(for preset: MilkPreset, in bundle: Bundle = .main) -> String? {
        guard let root = bundle.resourceURL?.appendingPathComponent("Presets", isDirectory: true) else {
            return nil
        }
        let path = root.appendingPathComponent(preset.file).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Absolute URL of the preset's bundled thumbnail, or nil when it is missing.
    static func thumbnailURL(for preset: MilkPreset, in bundle: Bundle = .main) -> URL? {
        guard let thumb = preset.thumb,
              let root = bundle.resourceURL?.appendingPathComponent("Presets", isDirectory: true) else {
            return nil
        }
        let url = root.appendingPathComponent(thumb)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func textureSearchPaths(in bundle: Bundle = .main) -> [String] {
        guard let root = bundle.resourceURL?.appendingPathComponent("Presets", isDirectory: true) else {
            return []
        }
        let tex = root.appendingPathComponent("textures", isDirectory: true).path
        if FileManager.default.fileExists(atPath: tex) { return [tex] }
        return [root.path]
    }

    private static func loadManifest() -> [MilkPreset] {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "Presets"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
               !decoded.presets.isEmpty {
                return decoded.presets.sorted { $0.id < $1.id }
            }
        }
        return [MilkPreset(id: 0, name: "Bundle presets missing", file: "files/placeholder.milk")]
    }

    private struct Manifest: Decodable {
        var presets: [MilkPreset]
    }

    private final class BundleToken {}
}
