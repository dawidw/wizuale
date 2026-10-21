import Foundation
import UIKit

/// Thin Swift wrapper around libprojectM 4.x. No tone mapping or post-processing.
final class ProjectMController {
    private var handle: OpaquePointer?
    private var loadedIndex = -1

    var isReady: Bool { handle != nil }

    func create(in context: EAGLContext, size: CGSize) {
        guard handle == nil else { return }
        EAGLContext.setCurrent(context)
        guard let created = projectm_create() else { return }
        handle = created
        projectm_set_window_size(created, size_t(size.width), size_t(size.height))
        projectm_set_soft_cut_duration(created, MilkPresetCatalog.softCutSeconds)
        projectm_set_preset_locked(created, true)
        projectm_set_hard_cut_enabled(created, false)
        projectm_set_beat_sensitivity(created, MicTuning.sensitivityDefault)
        projectm_set_fps(created, 60)

        let paths = MilkPresetCatalog.textureSearchPaths()
        if !paths.isEmpty {
            paths.withCStringArray { cPaths, count in
                projectm_set_texture_search_paths(created, UnsafeMutablePointer(mutating: cPaths), count)
            }
        }
        loadPreset(index: 0, smooth: false)
    }

    func destroy() {
        guard let handle else { return }
        projectm_destroy(handle)
        self.handle = nil
        loadedIndex = -1
    }

    func resize(_ size: CGSize) {
        guard let handle, size.width >= 1, size.height >= 1 else { return }
        projectm_set_window_size(handle, size_t(size.width), size_t(size.height))
    }

    func setBeatSensitivity(_ value: Float) {
        guard let handle else { return }
        projectm_set_beat_sensitivity(handle, MicTuning.clampSensitivity(value))
    }

    func render() {
        guard let handle else { return }
        projectm_opengl_render_frame(handle)
    }

    func addPCM(samples: [Int16], gain: Float) {
        guard let handle, !samples.isEmpty else { return }
        if abs(gain - 1) < 0.001 {
            samples.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                projectm_pcm_add_int16(handle, base, UInt32(ptr.count), PROJECTM_MONO)
            }
            return
        }
        var scaled = [Float]()
        scaled.reserveCapacity(samples.count)
        for sample in samples {
            scaled.append(Float(sample) / 32767 * gain)
        }
        scaled.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            projectm_pcm_add_float(handle, base, UInt32(ptr.count), PROJECTM_MONO)
        }
    }

    func loadPreset(index: Int, smooth: Bool) {
        guard let handle else { return }
        guard index != loadedIndex || !smooth else { return }
        guard let preset = MilkPresetCatalog.preset(at: index),
              let path = MilkPresetCatalog.absolutePath(for: preset) else {
            projectm_load_preset_file(handle, "idle://", smooth)
            loadedIndex = index
            return
        }
        path.withCString { cPath in
            projectm_load_preset_file(handle, cPath, smooth)
        }
        loadedIndex = index
    }
}

private extension Array where Element == String {
    func withCStringArray(_ body: (UnsafePointer<UnsafePointer<CChar>?>, Int) -> Void) {
        var pointers: [UnsafePointer<CChar>?] = []
        pointers.reserveCapacity(count)
        for string in self {
            pointers.append((string as NSString).utf8String)
        }
        pointers.withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress!, count)
        }
    }
}
