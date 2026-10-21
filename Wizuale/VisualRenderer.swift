import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

enum RendererError: LocalizedError {
    case noDevice
    case noQueue
    case layout(String)
    case library(String)
    case pipeline(String)

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "This Apple TV has no Metal device."
        case .noQueue:
            return "Metal could not create a command queue."
        case .layout(let message):
            return message
        case .library(let message):
            return "The shader library failed to load. \(message)"
        case .pipeline(let message):
            return "The picture pipeline failed to build. \(message)"
        }
    }
}

/// Slow wander on top of a preset. Targets ease in, so a frame never jumps.
/// The offset is applied to the uniforms only and is not stored back into the preset.
private struct Wander {
    var aim = SIMD4<Float>(0, 0, 0, 0)
    var value = SIMD4<Float>(0, 0, 0, 0)
    var remaining: Float = 0
    var slot = -1

    mutating func advance(slot: Int, time: Float, dt: Float) {
        if slot != self.slot {
            self.slot = slot
            remaining = 0
        }
        if remaining <= 0 {
            remaining = 3.4
            let seed = time * 0.23 + Float(slot) * 2.17
            aim = SIMD4(
                sin(seed * 1.7) * 0.014,
                sin(seed * 1.1 + 0.8) * 0.036,
                sin(seed * 1.9 + 1.4) * 0.048,
                sin(seed * 0.85 + 2.2) * 0.01
            )
        }
        remaining -= dt
        let follow = 1 - exp(-dt * 0.65)
        value += (aim - value) * follow
    }

    /// flow.x expansion, flow.y rotation, warp.x amount, persist.z hue.
    func apply(to uniforms: inout FrameUniforms, slot: Int, time: Float) {
        let bob = sin(time * 0.19 + Float(slot) * 1.3)
        uniforms.flow.x += value.x + bob * 0.004
        uniforms.flow.y += value.y + bob * 0.008
        uniforms.warp.x += value.z
        uniforms.warp.z += sin(time * 0.09 + Float(slot) * 0.7) * 0.035
        uniforms.persist.z += value.w
    }
}

/// Ping-pong feedback. One frame samples the previous picture through the warp,
/// then the screen samples that result. A single in-flight frame matches the
/// two textures: the completion handler is not on the main thread, so waiting
/// here cannot deadlock the GPU callback.
final class VisualRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let warpPipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private let state: RenderState
    private let beatClock: BeatClock
    private let micReceiver: MicReceiver
    private let gate = DispatchSemaphore(value: 1)

    private var textures: [MTLTexture] = []
    private var textureSize = SIMD2<Int>(0, 0)
    private var readIndex = 0

    private var time: Float = 0
    private var lastTick: CFTimeInterval = 0
    private var slotFrom = 0
    private var slotTo = 0
    private var modeT: Float = 1
    private var displayed: PresetParams
    private var wander = Wander()
    private var albumWeight: Float = 0
    private var album: AlbumColors?

    init(device: MTLDevice, state: RenderState, beatClock: BeatClock, micReceiver: MicReceiver) throws {
        if let problem = FrameUniforms.layoutProblem() {
            throw RendererError.layout(problem)
        }
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.noQueue
        }
        self.device = device
        self.queue = queue
        self.state = state
        self.beatClock = beatClock
        self.micReceiver = micReceiver

        let snapshot = state.snapshot()
        let slot = min(max(snapshot.targetIndex, 0), max(PresetLibrary.all.count - 1, 0))
        slotFrom = slot
        slotTo = slot
        displayed = PresetLibrary.all[slot].params

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            throw RendererError.library(error.localizedDescription)
        }
        guard
            let vertex = library.makeFunction(name: "fullscreenVertex"),
            let warp = library.makeFunction(name: "warpFragment"),
            let present = library.makeFunction(name: "presentFragment")
        else {
            throw RendererError.library("Missing fullscreenVertex, warpFragment, or presentFragment.")
        }
        warpPipeline = try Self.pipeline(
            device: device,
            vertex: vertex,
            fragment: warp,
            pixelFormat: .rgba16Float,
            label: "Warp"
        )
        presentPipeline = try Self.pipeline(
            device: device,
            vertex: vertex,
            fragment: present,
            pixelFormat: .bgra8Unorm,
            label: "Present"
        )
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt: Float
        if lastTick == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(max(Float(now - lastTick), 1.0 / 120.0), 1.0 / 20.0)
        }
        lastTick = now

        let snapshot = state.snapshot()
        if snapshot.paused { return }
        guard view.drawableSize.width >= 2, view.drawableSize.height >= 2 else { return }

        gate.wait()
        var committed = false
        defer {
            if !committed { gate.signal() }
        }

        guard
            let drawable = view.currentDrawable,
            let presentDescriptor = view.currentRenderPassDescriptor,
            let command = queue.makeCommandBuffer()
        else { return }

        command.label = "Wizuale"
        let size = Self.feedbackSize(for: view.drawableSize)
        guard ensureTextures(size) else { return }

        step(dt: dt, snapshot: snapshot)
        let musical = beatClock.sample(fallbackBPM: displayed.bpm)
        var uniforms = displayed.makeUniforms(
            resolution: SIMD2(Float(size.x), Float(size.y)),
            time: time,
            deltaTime: dt,
            modeFrom: PresetLibrary.mode(at: slotFrom),
            modeTo: PresetLibrary.mode(at: slotTo),
            modeT: modeT,
            album: album,
            albumWeight: albumWeight,
            beat: SIMD4(musical.kick, musical.downbeat, musical.beatPhase, musical.barPhase),
            music: SIMD4(musical.phrasePhase, musical.beatsPerBar, musical.hasRealTempo ? 1 : 0, 0)
        )
        uniforms.tempo.x = musical.bpm
        wander.apply(to: &uniforms, slot: slotTo, time: time)
        let heard = micReceiver.sample(dt: dt)
        uniforms.ear = SIMD4(heard.onset, heard.bass, heard.high, heard.loudness)
        uniforms.link = SIMD4(heard.presence, heard.flux, heard.lowMid, heard.mid)

        let writeIndex = 1 - readIndex
        guard let warp = command.makeRenderCommandEncoder(descriptor: Self.pass(textures[writeIndex])) else {
            return
        }
        warp.setRenderPipelineState(warpPipeline)
        warp.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        warp.setFragmentTexture(textures[readIndex], index: 0)
        warp.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        warp.endEncoding()

        guard let present = command.makeRenderCommandEncoder(descriptor: presentDescriptor) else { return }
        present.setRenderPipelineState(presentPipeline)
        present.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        present.setFragmentTexture(textures[writeIndex], index: 0)
        present.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        present.endEncoding()

        command.present(drawable)
        let gate = self.gate
        command.addCompletedHandler { _ in
            gate.signal()
        }
        committed = true
        command.commit()
        readIndex = writeIndex
    }

    private func step(dt: Float, snapshot: RenderSnapshot) {
        let lastIndex = max(PresetLibrary.all.count - 1, 0)
        let target = min(max(snapshot.targetIndex, 0), lastIndex)
        if target != slotTo {
            slotFrom = modeT > 0.5 ? slotTo : slotFrom
            slotTo = target
            modeT = 0
        }
        modeT = min(1, modeT + dt / PresetLibrary.blendDuration)
        // While two pictures are mixing, ease the warp across the same window.
        // Once the crossfade is done, catch album colors at the old rate.
        let rate: Float = modeT < 0.999 ? 0.42 : 1.6
        let blend = 1 - exp(-dt * rate)
        displayed = displayed.lerped(toward: PresetLibrary.all[slotTo].params, by: blend)
        wander.advance(slot: slotTo, time: time, dt: dt)
        time += dt

        if snapshot.wantsAlbum, let incoming = snapshot.album {
            if let current = album {
                album = AlbumColors(
                    first: mix(current.first, incoming.first, blend),
                    second: mix(current.second, incoming.second, blend),
                    third: mix(current.third, incoming.third, blend)
                )
            } else {
                album = incoming
            }
            albumWeight = mix(albumWeight, 1, blend)
        } else {
            albumWeight = mix(albumWeight, 0, blend)
        }
    }

    /// 4K draws into a 1920-wide history. The present pass still fills the TV.
    private static func feedbackSize(for drawable: CGSize) -> SIMD2<Int> {
        var width = max(drawable.width, 2)
        var height = max(drawable.height, 2)
        let longest = max(width, height)
        if longest > 1920 {
            let scale = 1920.0 / longest
            width *= scale
            height *= scale
        }
        var w = Int(width.rounded(.down))
        var h = Int(height.rounded(.down))
        if w % 2 != 0 { w -= 1 }
        if h % 2 != 0 { h -= 1 }
        return SIMD2(max(w, 2), max(h, 2))
    }

    /// Private storage is uninitialized until a render pass clears it. The clear
    /// is committed on its own so a later failed frame cannot leave garbage in the history.
    private func ensureTextures(_ size: SIMD2<Int>) -> Bool {
        if textures.count == 2, textureSize.x == size.x, textureSize.y == size.y {
            return true
        }
        guard
            let first = makeTexture(size),
            let second = makeTexture(size),
            let command = queue.makeCommandBuffer()
        else { return false }
        command.label = "Clear feedback"
        clear(first, command)
        clear(second, command)
        command.commit()
        command.waitUntilCompleted()
        textures = [first, second]
        textureSize = size
        readIndex = 0
        return true
    }

    private func makeTexture(_ size: SIMD2<Int>) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: size.x,
            height: size.y,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Feedback"
        return texture
    }

    /// Private textures cannot be cleared from the CPU. A render pass can.
    private func clear(_ texture: MTLTexture, _ command: MTLCommandBuffer) {
        let descriptor = Self.pass(texture)
        descriptor.colorAttachments[0].loadAction = .clear
        command.makeRenderCommandEncoder(descriptor: descriptor)?.endEncoding()
    }

    private static func pass(_ texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        return descriptor
    }

    private static func pipeline(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        pixelFormat: MTLPixelFormat,
        label: String
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.pipeline(error.localizedDescription)
        }
    }
}
