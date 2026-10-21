import simd

/// Packed exactly like `FrameUniforms` in Shaders.metal. 16 bytes of header,
/// then fourteen float4s. `layoutProblem()` is checked before the first frame
/// so a padding mismatch shows up as an on-screen message instead of a scrambled picture.
struct FrameUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var deltaTime: Float
    var flow: SIMD4<Float>
    var warp: SIMD4<Float>
    var center: SIMD4<Float>
    var persist: SIMD4<Float>
    var wave: SIMD4<Float>
    var shape: SIMD4<Float>
    var grade: SIMD4<Float>
    var style: SIMD4<Float>
    var tempo: SIMD4<Float>
    var hole: SIMD4<Float>
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var baseColor: SIMD4<Float>

    static let byteCount = 240

    static func layoutProblem() -> String? {
        let size = MemoryLayout<FrameUniforms>.size
        let stride = MemoryLayout<FrameUniforms>.stride
        let flow = MemoryLayout<FrameUniforms>.offset(of: \.flow) ?? -1
        let color0 = MemoryLayout<FrameUniforms>.offset(of: \.color0) ?? -1
        let base = MemoryLayout<FrameUniforms>.offset(of: \.baseColor) ?? -1
        guard size == byteCount, stride == byteCount, flow == 16, color0 == 176, base == 224 else {
            return "Shader uniforms are misaligned (size \(size), stride \(stride), flow \(flow), color0 \(color0), base \(base)). Expected 240 bytes."
        }
        return nil
    }
}

struct AlbumColors: Equatable, Sendable {
    var first: SIMD3<Float>
    var second: SIMD3<Float>
    var third: SIMD3<Float>
}

func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}
