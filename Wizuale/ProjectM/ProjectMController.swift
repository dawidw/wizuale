import Foundation
import UIKit
import OpenGLES
import Darwin

/// Thin Swift wrapper around libprojectM 4.x. No tone mapping or post-processing.
final class ProjectMController {
    private var handle: OpaquePointer?
    private var loadedIndex = -1

    var isReady: Bool { handle != nil }

    func create(in context: EAGLContext, size: CGSize) {
        guard handle == nil else { return }
        EAGLContext.setCurrent(context)
        // Apple has no EGL/glXGetProcAddress, so resolve GL symbols from the
        // already-loaded OpenGLES framework via dlsym(RTLD_DEFAULT, ...).
        // tvOS uses EAGL, which projectM's resolver can't probe (it expects CGL/EGL).
        // Our dlsym loader works with the current EAGL context, so skip the strict gate.
        setenv("PROJECTM_GLRESOLVER_STRICT_CONTEXT_GATE", "0", 1)
        projectm_set_log_level(PROJECTM_LOG_LEVEL_INFO, false)
        projectm_set_log_callback({ msg, level, _ in
            if let msg { NSLog("[projectM %d] %@", Int(level.rawValue), String(cString: msg)) }
        }, false, nil)
        let loader: projectm_load_proc = { name, _ in
            guard let name else { return nil }
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        }
        guard let created = projectm_create_with_opengl_load_proc(loader, nil) ?? projectm_create() else {
            NSLog("[Wizuale] projectm_create failed; GL_VERSION=%@", String(cString: glGetString(GLenum(GL_VERSION))))
            return
        }
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

    /// GLKView draws into its own framebuffer (not 0), so render into whatever is bound.
    func render() {
        guard let handle else { return }
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &fbo)
        projectm_opengl_render_frame_fbo(handle, UInt32(fbo))
    }

    /// Mono floats in -1...1 (already paced and levelled by ProjectMAudioHub).
    func addPCM(floats: [Float]) {
        guard let handle, !floats.isEmpty else { return }
        floats.withUnsafeBufferPointer { ptr in
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
