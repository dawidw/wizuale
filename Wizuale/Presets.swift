import simd

/// Draw styles in Shaders.metal. The raw value is the `mode` the shader branches on.
enum VisualMode: Int, CaseIterable, Identifiable {
    case dottedTunnel = 0
    case tealDust = 1
    case greenRays = 2
    case orbGrid = 3
    case waveTangle = 4
    case coralWarp = 5
    case plasmaVeins = 6
    case spiralArms = 7
    case kaleidoMirror = 8
    case fractalWell = 9
    case barStorm = 10
    case vortexFilament = 11
    case prismWheel = 12
    case neonComet = 13
    case pulseRings = 14
    case starLattice = 15
    case bassShockwave = 16
    case wireWeb = 17
    case deepMandala = 18
    case spectrumHalo = 19

    var id: Int { rawValue }
}

/// One frame of look parameters. Rates are per second, so the picture stays
/// the same if a frame arrives late. Add a preset by appending to `PresetLibrary.all`.
struct PresetParams: Equatable {
    var expansion: Float
    var rotation: Float
    var rotationInner: Float
    var kaleidoSpin: Float
    var warp: Float
    var warpFrequency: Float
    var warpSpeed: Float
    var radialWarp: Float
    var centerAmplitude: Float
    var goo: Float
    var folds: Float
    var kaleidoMix: Float
    var decayTau: Float
    var blur: Float
    var hueShift: Float
    var chroma: Float
    var frequency: Float
    var thickness: Float
    var radiusOffset: Float
    var count: Float
    var radius: Float
    var softness: Float
    var intensity: Float
    var sparkle: Float
    var saturation: Float
    var vignette: Float
    var exposure: Float
    var baseLevel: Float
    var emissionGain: Float
    var pulseAmount: Float
    var bpm: Float
    var centerHole: Float
    var centerDark: Float
    var grain: Float
    var color0: SIMD3<Float>
    var color1: SIMD3<Float>
    var color2: SIMD3<Float>
    var base: SIMD3<Float>
    var albumInfluence: Float

    func lerped(toward other: PresetParams, by t: Float) -> PresetParams {
        func m(_ a: Float, _ b: Float) -> Float { mix(a, b, t) }
        func c(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { mix(a, b, t) }
        return PresetParams(
            expansion: m(expansion, other.expansion),
            rotation: m(rotation, other.rotation),
            rotationInner: m(rotationInner, other.rotationInner),
            kaleidoSpin: m(kaleidoSpin, other.kaleidoSpin),
            warp: m(warp, other.warp),
            warpFrequency: m(warpFrequency, other.warpFrequency),
            warpSpeed: m(warpSpeed, other.warpSpeed),
            radialWarp: m(radialWarp, other.radialWarp),
            centerAmplitude: m(centerAmplitude, other.centerAmplitude),
            goo: m(goo, other.goo),
            folds: m(folds, other.folds),
            kaleidoMix: m(kaleidoMix, other.kaleidoMix),
            decayTau: m(decayTau, other.decayTau),
            blur: m(blur, other.blur),
            hueShift: m(hueShift, other.hueShift),
            chroma: m(chroma, other.chroma),
            frequency: m(frequency, other.frequency),
            thickness: m(thickness, other.thickness),
            radiusOffset: m(radiusOffset, other.radiusOffset),
            count: m(count, other.count),
            radius: m(radius, other.radius),
            softness: m(softness, other.softness),
            intensity: m(intensity, other.intensity),
            sparkle: m(sparkle, other.sparkle),
            saturation: m(saturation, other.saturation),
            vignette: m(vignette, other.vignette),
            exposure: m(exposure, other.exposure),
            baseLevel: m(baseLevel, other.baseLevel),
            emissionGain: m(emissionGain, other.emissionGain),
            pulseAmount: m(pulseAmount, other.pulseAmount),
            bpm: m(bpm, other.bpm),
            centerHole: m(centerHole, other.centerHole),
            centerDark: m(centerDark, other.centerDark),
            grain: m(grain, other.grain),
            color0: c(color0, other.color0),
            color1: c(color1, other.color1),
            color2: c(color2, other.color2),
            base: c(base, other.base),
            albumInfluence: m(albumInfluence, other.albumInfluence)
        )
    }

    func makeUniforms(
        resolution: SIMD2<Float>,
        time: Float,
        deltaTime: Float,
        modeFrom: Int,
        modeTo: Int,
        modeT: Float,
        album: AlbumColors?,
        albumWeight: Float,
        beat: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        music: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        ear: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        link: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0)
    ) -> FrameUniforms {
        let influence = albumInfluence * albumWeight
        let mixed0 = mix(color0, album?.first ?? color0, influence)
        let mixed1 = mix(color1, album?.second ?? color1, influence)
        let mixed2 = mix(color2, album?.third ?? color2, influence)
        func v4(_ c: SIMD3<Float>) -> SIMD4<Float> { SIMD4(c.x, c.y, c.z, 1) }
        return FrameUniforms(
            resolution: resolution,
            time: time,
            deltaTime: deltaTime,
            flow: SIMD4(expansion, rotation, rotationInner, kaleidoSpin),
            warp: SIMD4(warp, warpFrequency, warpSpeed, radialWarp),
            center: SIMD4(centerAmplitude, goo, folds, kaleidoMix),
            persist: SIMD4(decayTau, blur, hueShift, chroma),
            wave: SIMD4(0, frequency, thickness, radiusOffset),
            shape: SIMD4(count, radius, softness, intensity),
            grade: SIMD4(sparkle, 0, saturation, vignette),
            style: SIMD4(exposure, baseLevel, emissionGain, pulseAmount),
            tempo: SIMD4(bpm, Float(modeFrom), Float(modeTo), modeT),
            hole: SIMD4(centerHole, centerDark, grain, 0),
            beat: beat,
            music: music,
            color0: v4(mixed0),
            color1: v4(mixed1),
            color2: v4(mixed2),
            baseColor: v4(base),
            ear: ear,
            link: link
        )
    }
}

struct Preset: Identifiable, Equatable {
    var mode: VisualMode
    var name: String
    var cyclesAutomatically: Bool
    var params: PresetParams

    var id: VisualMode { mode }
}

enum PresetLibrary {
    static let cycleHold: Double = 45
    static let blendDuration: Float = 1.35

    /// Index 0 is the first card after Auto. Auto itself is `PresetWire.auto`.
    /// The phone and the TV both read this array; do not reorder it.
    static let all: [Preset] = [
        make(.dottedTunnel, "Dotted Tunnel", cycles: true, album: 0.42, classic(
            expansion: 0.48, rotation: 0.1, rotationInner: 0.38, kaleidoSpin: 0.02,
            warp: 0.44, warpFrequency: 14, warpSpeed: 0.78, radialWarp: 0.04,
            goo: 0.08, folds: 1, kaleidoMix: 0, decayTau: 0.62, blur: 0.35,
            hueShift: 0.12, chroma: 0.55, frequency: 16, thickness: 0.007,
            count: 1, radius: 0.2, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.45, exposure: 1.0, pulseAmount: 0.14, bpm: 118,
            centerHole: 0.06, centerDark: 0.85, grain: 0,
            c0: SIMD3(0.05, 0.82, 0.78), c1: SIMD3(0.12, 0.55, 0.95), c2: SIMD3(0.02, 0.38, 0.62)
        )),
        make(.tealDust, "Teal Dust", cycles: true, album: 0.44, classic(
            expansion: 0.08, rotation: 0.14, rotationInner: 0.04, kaleidoSpin: 0.02,
            warp: 0.22, warpFrequency: 2.8, warpSpeed: 0.16, radialWarp: 0.02,
            goo: 0.1, folds: 1, kaleidoMix: 0, decayTau: 0.72, blur: 0.55,
            hueShift: 0.06, chroma: 0.4, frequency: 3.2, thickness: 0.012,
            count: 1, radius: 0.2, softness: 1, intensity: 0.44,
            sparkle: 0.2, saturation: 1.42, exposure: 1.0, pulseAmount: 0.1, bpm: 96,
            centerHole: 0.02, centerDark: 0.2, grain: 0,
            c0: SIMD3(0.08, 0.9, 0.82), c1: SIMD3(0.15, 0.65, 0.95), c2: SIMD3(0.05, 0.45, 0.72)
        )),
        make(.greenRays, "Green Rays", cycles: true, album: 0.4, classic(
            expansion: 0.78, rotation: 0.05, rotationInner: 0.14, kaleidoSpin: 0,
            warp: 0.12, warpFrequency: 2.2, warpSpeed: 0.2, radialWarp: 0.02,
            goo: 0.02, folds: 1, kaleidoMix: 0, decayTau: 0.55, blur: 0.32,
            hueShift: 0.04, chroma: 0.35, frequency: 5, thickness: 0.005,
            count: 1, radius: 0.2, softness: 1, intensity: 0.48,
            sparkle: 0, saturation: 1.5, exposure: 1.0, pulseAmount: 0.16, bpm: 128,
            centerHole: 0.02, centerDark: 0.7, grain: 0,
            c0: SIMD3(0.15, 0.95, 0.22), c1: SIMD3(0.35, 1, 0.45), c2: SIMD3(0.02, 0.55, 0.18)
        )),
        make(.orbGrid, "Orb & Grid", cycles: true, album: 0.46, classic(
            expansion: 0.12, rotation: 0.08, rotationInner: 0.05, kaleidoSpin: 0,
            warp: 0.18, warpFrequency: 5.5, warpSpeed: 0.26, radialWarp: 0.03,
            goo: 0.06, folds: 1, kaleidoMix: 0, decayTau: 0.64, blur: 0.38,
            hueShift: 0.08, chroma: 0.5, frequency: 6, thickness: 0.008,
            count: 1, radius: 0.2, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.48, exposure: 1.0, pulseAmount: 0.13, bpm: 110,
            centerHole: 0.03, centerDark: 0.55, grain: 0,
            c0: SIMD3(0.15, 0.45, 1), c1: SIMD3(0.95, 0.12, 0.18), c2: SIMD3(0.55, 0.75, 1)
        )),
        make(.waveTangle, "Wave Tangle", cycles: true, album: 0.48, classic(
            expansion: 0.1, rotation: 0.32, rotationInner: 0.1, kaleidoSpin: 0.02,
            warp: 0.18, warpFrequency: 6.2, warpSpeed: 0.32, radialWarp: 0.03,
            goo: 0.05, folds: 1, kaleidoMix: 0, decayTau: 0.7, blur: 0.36,
            hueShift: 0.1, chroma: 0.55, frequency: 8, thickness: 0.0045,
            count: 6, radius: 0.3, softness: 1, intensity: 0.47,
            sparkle: 0, saturation: 1.4, exposure: 1.0, pulseAmount: 0.12, bpm: 114,
            centerHole: 0.04, centerDark: 0.75, grain: 0,
            c0: SIMD3(0.88, 0.92, 1), c1: SIMD3(0.55, 0.12, 0.65), c2: SIMD3(0.75, 0.15, 0.35)
        )),
        make(.coralWarp, "Coral Warp", cycles: true, album: 0.5, classic(
            expansion: 0.08, rotation: 0.12, rotationInner: 0.05, kaleidoSpin: 0.05,
            warp: 0.52, warpFrequency: 4.2, warpSpeed: 0.28, radialWarp: 0.04,
            goo: 0.24, folds: 3, kaleidoMix: 0.85, decayTau: 0.76, blur: 0.72,
            hueShift: 0.1, chroma: 0.55, frequency: 3.8, thickness: 0.014,
            count: 2, radius: 0.2, softness: 1, intensity: 0.45,
            sparkle: 0, saturation: 1.52, exposure: 1.0, pulseAmount: 0.1, bpm: 92,
            centerHole: 0.03, centerDark: 0.15, grain: 0,
            c0: SIMD3(0.95, 0.28, 0.32), c1: SIMD3(0.15, 0.75, 0.95), c2: SIMD3(0.35, 0.95, 0.72)
        )),
        make(.plasmaVeins, "Plasma Veins", cycles: true, album: 0.44, classic(
            expansion: 0.1, rotation: 0.16, rotationInner: 0.05, kaleidoSpin: 0.03,
            warp: 0.34, warpFrequency: 5.2, warpSpeed: 0.28, radialWarp: 0.04,
            goo: 0.12, folds: 1, kaleidoMix: 0, decayTau: 0.66, blur: 0.48,
            hueShift: 0.14, chroma: 0.55, frequency: 5.8, thickness: 0.009,
            count: 1, radius: 0.2, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.46, exposure: 1.0, pulseAmount: 0.11, bpm: 102,
            centerHole: 0, centerDark: 0.12, grain: 0,
            c0: SIMD3(0.95, 0.18, 0.55), c1: SIMD3(0.2, 0.92, 1), c2: SIMD3(1, 0.82, 0.22)
        )),
        make(.spiralArms, "Spiral Arms", cycles: true, album: 0.48, classic(
            expansion: 0.42, rotation: 0.55, rotationInner: 0.2, kaleidoSpin: 0.05,
            warp: 0.24, warpFrequency: 7.5, warpSpeed: 0.38, radialWarp: 0.05,
            goo: 0.08, folds: 1, kaleidoMix: 0, decayTau: 0.6, blur: 0.42,
            hueShift: 0.18, chroma: 0.7, frequency: 8.5, thickness: 0.008,
            count: 8, radius: 0.34, softness: 1.1, intensity: 0.46,
            sparkle: 0, saturation: 1.44, exposure: 1.0, pulseAmount: 0.14, bpm: 106,
            centerHole: 0.04, centerDark: 0.45, grain: 0,
            c0: SIMD3(1, 0.22, 0.55), c1: SIMD3(1, 0.78, 0.15), c2: SIMD3(0.15, 0.92, 0.82)
        )),
        make(.kaleidoMirror, "Kaleido Mirror", cycles: true, album: 0.48, classic(
            expansion: 0.18, rotation: 0.26, rotationInner: 0.1, kaleidoSpin: 0.1,
            warp: 0.2, warpFrequency: 6.4, warpSpeed: 0.3, radialWarp: 0.04,
            goo: 0.08, folds: 8, kaleidoMix: 1, decayTau: 0.58, blur: 0.38,
            hueShift: 0.14, chroma: 0.62, frequency: 6, thickness: 0.006,
            count: 8, radius: 0.3, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.42, exposure: 1.0, pulseAmount: 0.13, bpm: 108,
            centerHole: 0.05, centerDark: 0.5, grain: 0,
            c0: SIMD3(1, 0.72, 0.2), c1: SIMD3(0.52, 0.18, 1), c2: SIMD3(0.72, 0.92, 1)
        )),
        make(.fractalWell, "Fractal Well", cycles: true, album: 0.46, classic(
            expansion: 0.38, rotation: 0.16, rotationInner: 0.36, kaleidoSpin: 0.04,
            warp: 0.18, warpFrequency: 9, warpSpeed: 0.4, radialWarp: 0.05,
            goo: 0.06, folds: 4, kaleidoMix: 0.75, decayTau: 0.56, blur: 0.38,
            hueShift: 0.16, chroma: 0.8, frequency: 9.5, thickness: 0.007,
            count: 4, radius: 0.26, softness: 1.3, intensity: 0.46,
            sparkle: 0, saturation: 1.4, exposure: 1.0, pulseAmount: 0.14, bpm: 116,
            centerHole: 0.05, centerDark: 0.82, grain: 0,
            c0: SIMD3(0.48, 0.15, 1), c1: SIMD3(1, 0.22, 0.55), c2: SIMD3(0.15, 0.88, 0.82)
        )),
        make(.barStorm, "Bar Storm", cycles: true, album: 0.5, classic(
            expansion: 0.1, rotation: 0.06, rotationInner: 0.03, kaleidoSpin: 0,
            warp: 0.14, warpFrequency: 4.2, warpSpeed: 0.22, radialWarp: 0.02,
            goo: 0.04, folds: 1, kaleidoMix: 0, decayTau: 0.72, blur: 0.35,
            hueShift: 0.1, chroma: 0.48, frequency: 5, thickness: 0.009,
            count: 16, radius: 0.2, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.44, exposure: 1.0, pulseAmount: 0.12, bpm: 112,
            centerHole: 0, centerDark: 0.1, grain: 0,
            c0: SIMD3(0.2, 1, 0.45), c1: SIMD3(1, 0.82, 0.2), c2: SIMD3(0.2, 0.72, 1)
        )),
        make(.vortexFilament, "Vortex Filament", cycles: true, album: 0.44, classic(
            expansion: 0.22, rotation: 0.65, rotationInner: 0.55, kaleidoSpin: 0.04,
            warp: 0.3, warpFrequency: 6.6, warpSpeed: 0.38, radialWarp: 0.06,
            goo: 0.08, folds: 1, kaleidoMix: 0, decayTau: 0.64, blur: 0.45,
            hueShift: 0.1, chroma: 0.65, frequency: 6, thickness: 0.009,
            count: 4, radius: 0.22, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.38, exposure: 1.0, pulseAmount: 0.15, bpm: 114,
            centerHole: 0.04, centerDark: 0.88, grain: 0,
            c0: SIMD3(0.2, 0.52, 1), c1: SIMD3(0.82, 0.9, 1), c2: SIMD3(0.35, 0.12, 0.92)
        )),
        make(.prismWheel, "Prism Wheel", cycles: true, album: 0.44, classic(
            expansion: 0.14, rotation: 0.36, rotationInner: 0.12, kaleidoSpin: 0.12,
            warp: 0.24, warpFrequency: 7.6, warpSpeed: 0.4, radialWarp: 0.05,
            goo: 0.1, folds: 12, kaleidoMix: 1, decayTau: 0.56, blur: 0.42,
            hueShift: 0.38, chroma: 0.72, frequency: 8, thickness: 0.004,
            count: 12, radius: 0.4, softness: 1, intensity: 0.45,
            sparkle: 0, saturation: 1.42, exposure: 1.0, pulseAmount: 0.12, bpm: 120,
            centerHole: 0.06, centerDark: 0.4, grain: 0,
            c0: SIMD3(0.22, 0.42, 1), c1: SIMD3(0.72, 0.85, 1), c2: SIMD3(0.58, 0.15, 1)
        )),
        make(.neonComet, "Neon Comet", cycles: true, album: 0.42, classic(
            expansion: 0.55, rotation: 0.08, rotationInner: 0.12, kaleidoSpin: 0.02,
            warp: 0.16, warpFrequency: 3.5, warpSpeed: 0.22, radialWarp: 0.03,
            goo: 0.04, folds: 1, kaleidoMix: 0, decayTau: 0.58, blur: 0.34,
            hueShift: 0.12, chroma: 0.5, frequency: 4, thickness: 0.006,
            count: 6, radius: 0.2, softness: 1, intensity: 0.45,
            sparkle: 0.15, saturation: 1.46, exposure: 1.0, pulseAmount: 0.14, bpm: 122,
            centerHole: 0.03, centerDark: 0.6, grain: 0,
            c0: SIMD3(1, 0.35, 0.12), c1: SIMD3(0.95, 0.15, 0.85), c2: SIMD3(0.25, 0.85, 1)
        )),
        make(.pulseRings, "Pulse Rings", cycles: true, album: 0.4, classic(
            expansion: 0.2, rotation: 0.04, rotationInner: 0.08, kaleidoSpin: 0,
            warp: 0.14, warpFrequency: 7, warpSpeed: 0.3, radialWarp: 0.03,
            goo: 0.05, folds: 1, kaleidoMix: 0, decayTau: 0.6, blur: 0.36,
            hueShift: 0.08, chroma: 0.45, frequency: 11, thickness: 0.007,
            count: 1, radius: 0.2, softness: 1, intensity: 0.44,
            sparkle: 0, saturation: 1.4, exposure: 1.0, pulseAmount: 0.13, bpm: 108,
            centerHole: 0.05, centerDark: 0.7, grain: 0,
            c0: SIMD3(0.12, 0.88, 0.95), c1: SIMD3(0.55, 0.25, 1), c2: SIMD3(0.08, 0.55, 0.88)
        )),
        make(.starLattice, "Star Lattice", cycles: true, album: 0.42, classic(
            expansion: 0.35, rotation: 0.06, rotationInner: 0.1, kaleidoSpin: 0,
            warp: 0.2, warpFrequency: 5, warpSpeed: 0.24, radialWarp: 0.03,
            goo: 0.04, folds: 1, kaleidoMix: 0, decayTau: 0.62, blur: 0.32,
            hueShift: 0.06, chroma: 0.42, frequency: 6, thickness: 0.008,
            count: 1, radius: 0.2, softness: 1, intensity: 0.43,
            sparkle: 0, saturation: 1.38, exposure: 1.0, pulseAmount: 0.11, bpm: 104,
            centerHole: 0.02, centerDark: 0.65, grain: 0,
            c0: SIMD3(0.1, 0.75, 0.88), c1: SIMD3(0.45, 0.55, 1), c2: SIMD3(0.05, 0.42, 0.72)
        )),
        make(.bassShockwave, "Bass Shockwave", cycles: true, album: 0.48, classic(
            expansion: 0.28, rotation: 0.02, rotationInner: 0.04, kaleidoSpin: 0,
            warp: 0.12, warpFrequency: 8, warpSpeed: 0.34, radialWarp: 0.04,
            goo: 0.03, folds: 1, kaleidoMix: 0, decayTau: 0.54, blur: 0.3,
            hueShift: 0.06, chroma: 0.4, frequency: 12, thickness: 0.008,
            count: 1, radius: 0.2, softness: 1, intensity: 0.48,
            sparkle: 0, saturation: 1.48, exposure: 1.0, pulseAmount: 0.17, bpm: 124,
            centerHole: 0.04, centerDark: 0.75, grain: 0,
            c0: SIMD3(0.95, 0.22, 0.55), c1: SIMD3(1, 0.55, 0.15), c2: SIMD3(0.85, 0.15, 0.95)
        )),
        make(.wireWeb, "Wire Web", cycles: true, album: 0.4, classic(
            expansion: 0.06, rotation: 0.22, rotationInner: 0.08, kaleidoSpin: 0.03,
            warp: 0.28, warpFrequency: 6.8, warpSpeed: 0.32, radialWarp: 0.04,
            goo: 0.1, folds: 2, kaleidoMix: 0.5, decayTau: 0.68, blur: 0.4,
            hueShift: 0.1, chroma: 0.48, frequency: 7.5, thickness: 0.006,
            count: 1, radius: 0.2, softness: 1, intensity: 0.44,
            sparkle: 0, saturation: 1.36, exposure: 1.0, pulseAmount: 0.1, bpm: 100,
            centerHole: 0.02, centerDark: 0.25, grain: 0,
            c0: SIMD3(0.55, 0.85, 1), c1: SIMD3(0.95, 0.45, 0.95), c2: SIMD3(0.35, 0.95, 0.65)
        )),
        make(.deepMandala, "Deep Mandala", cycles: true, album: 0.44, classic(
            expansion: 0.12, rotation: 0.42, rotationInner: 0.14, kaleidoSpin: 0.14,
            warp: 0.22, warpFrequency: 7.2, warpSpeed: 0.36, radialWarp: 0.05,
            goo: 0.09, folds: 10, kaleidoMix: 1, decayTau: 0.6, blur: 0.4,
            hueShift: 0.22, chroma: 0.68, frequency: 7, thickness: 0.0035,
            count: 10, radius: 0.38, softness: 1, intensity: 0.45,
            sparkle: 0, saturation: 1.44, exposure: 1.0, pulseAmount: 0.12, bpm: 118,
            centerHole: 0.06, centerDark: 0.55, grain: 0,
            c0: SIMD3(0.85, 0.2, 0.95), c1: SIMD3(0.25, 0.55, 1), c2: SIMD3(1, 0.55, 0.25)
        )),
        make(.spectrumHalo, "Spectrum Halo", cycles: true, album: 0.5, classic(
            expansion: 0.08, rotation: 0.18, rotationInner: 0.06, kaleidoSpin: 0.04,
            warp: 0.16, warpFrequency: 5.5, warpSpeed: 0.28, radialWarp: 0.03,
            goo: 0.05, folds: 1, kaleidoMix: 0, decayTau: 0.66, blur: 0.38,
            hueShift: 0.14, chroma: 0.55, frequency: 6, thickness: 0.005,
            count: 24, radius: 0.36, softness: 1, intensity: 0.46,
            sparkle: 0, saturation: 1.46, exposure: 1.0, pulseAmount: 0.13, bpm: 110,
            centerHole: 0.08, centerDark: 0.65, grain: 0,
            c0: SIMD3(0.2, 0.95, 0.55), c1: SIMD3(1, 0.75, 0.2), c2: SIMD3(0.18, 0.65, 1)
        ))
    ]

    static func mode(at slot: Int) -> Int {
        guard all.indices.contains(slot) else { return 0 }
        return all[slot].mode.rawValue
    }

    static func index(after index: Int, step: Int) -> Int {
        let count = all.count
        return (index + step + count) % count
    }

    static func nextCyclingIndex(after index: Int) -> Int? {
        guard !all.isEmpty else { return nil }
        var cursor = index
        for _ in 0..<all.count {
            cursor = Self.index(after: cursor, step: 1)
            if all[cursor].cyclesAutomatically { return cursor }
        }
        return nil
    }

    private static func make(_ mode: VisualMode, _ name: String, cycles: Bool, album: Float, _ params: PresetParams) -> Preset {
        var tuned = params
        tuned.albumInfluence = album
        return Preset(mode: mode, name: name, cyclesAutomatically: cycles, params: tuned)
    }

    /// Shared dark-base MilkDrop tuning for the classic set.
    private static func classic(
        expansion: Float, rotation: Float, rotationInner: Float, kaleidoSpin: Float,
        warp: Float, warpFrequency: Float, warpSpeed: Float, radialWarp: Float,
        goo: Float, folds: Float, kaleidoMix: Float, decayTau: Float, blur: Float,
        hueShift: Float, chroma: Float, frequency: Float, thickness: Float,
        count: Float, radius: Float, softness: Float, intensity: Float,
        sparkle: Float, saturation: Float, exposure: Float, pulseAmount: Float, bpm: Float,
        centerHole: Float, centerDark: Float, grain: Float,
        c0: SIMD3<Float>, c1: SIMD3<Float>, c2: SIMD3<Float>
    ) -> PresetParams {
        PresetParams(
            expansion: expansion, rotation: rotation, rotationInner: rotationInner, kaleidoSpin: kaleidoSpin,
            warp: warp, warpFrequency: warpFrequency, warpSpeed: warpSpeed, radialWarp: radialWarp,
            centerAmplitude: 0, goo: goo, folds: folds, kaleidoMix: kaleidoMix,
            decayTau: decayTau, blur: blur, hueShift: hueShift, chroma: chroma,
            frequency: frequency, thickness: thickness, radiusOffset: 0,
            count: count, radius: radius, softness: softness, intensity: intensity,
            sparkle: sparkle, saturation: saturation, vignette: 0.24,
            exposure: min(exposure, 1.0), baseLevel: 0, emissionGain: 0.32, pulseAmount: pulseAmount,
            bpm: bpm, centerHole: centerHole, centerDark: centerDark, grain: grain,
            color0: c0, color1: c1, color2: c2,
            base: SIMD3(0.008, 0.006, 0.014), albumInfluence: 0
        )
    }
}
