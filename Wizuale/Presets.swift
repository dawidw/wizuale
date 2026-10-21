import simd

/// Draw styles in Shaders.metal. The raw value is the `mode` the shader branches on.
enum VisualMode: Int, CaseIterable, Identifiable {
    case spiral = 0
    case petals = 1
    case ember = 2
    case tunnel = 3
    case silk = 4
    case wheel = 5
    case aurora = 6
    case bloom = 7
    case border = 8
    case drift = 9
    case scope = 10
    case mirror = 11
    case plasma = 12
    case warpStars = 13
    case well = 14
    case bleed = 15
    case vortex = 16
    case mesh = 17
    case water = 18
    case flame = 19

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
    /// MilkDrop presets rotate on their own. The calmer ones stay until you swipe away.
    var cyclesAutomatically: Bool
    var params: PresetParams

    var id: VisualMode { mode }
}

enum PresetLibrary {
    /// How long a self-cycling preset holds before it may advance.
    /// A matched tempo waits for the next 8-bar phrase after this, instead of cutting on the timer.
    static let cycleHold: Double = 45
    /// Emit crossfade. Warp parameters ease across this window in the renderer.
    static let blendDuration: Float = 1.35

    /// Index 0 is the first card after Auto. Auto itself is `PresetWire.auto`.
    /// The phone and the TV both read this array; do not reorder it.
    static let all: [Preset] = [
        make(.spiral, "Spiral Star", cycles: true, album: 0.52, PresetParams(
            expansion: 0.42, rotation: 0.55, rotationInner: 0.2, kaleidoSpin: 0.08,
            warp: 0.28, warpFrequency: 7.0, warpSpeed: 0.35, radialWarp: 0.05,
            centerAmplitude: 0, goo: 0.09, folds: 8, kaleidoMix: 1,
            decayTau: 0.62, blur: 0.6, hueShift: 0.22, chroma: 0.7,
            frequency: 7.5, thickness: 0.01, radiusOffset: 0,
            count: 8, radius: 0.32, softness: 1.2, intensity: 1,
            sparkle: 0.04, saturation: 1.45, vignette: 0.18,
            exposure: 2.6, baseLevel: 0, emissionGain: 1, pulseAmount: 0.14,
            bpm: 96, centerHole: 0.045, centerDark: 2.2, grain: 0.00045,
            color0: SIMD3(1, 0.12, 0.62), color1: SIMD3(1, 0.86, 0.12), color2: SIMD3(0.1, 0.95, 0.82),
            base: SIMD3(0.015, 0.008, 0.02), albumInfluence: 0
        )),
        make(.petals, "Petal Veil", cycles: true, album: 0.5, PresetParams(
            expansion: 0.34, rotation: 0.22, rotationInner: 0.05, kaleidoSpin: 0.04,
            warp: 0.32, warpFrequency: 6.2, warpSpeed: 0.32, radialWarp: 0.08,
            centerAmplitude: 0, goo: 0.08, folds: 8, kaleidoMix: 1,
            decayTau: 0.7, blur: 0.45, hueShift: 0.06, chroma: 0.3,
            frequency: 7, thickness: 0.0036, radiusOffset: 0.02,
            count: 7, radius: 0.18, softness: 1.35, intensity: 1.15,
            sparkle: 0.02, saturation: 1.4, vignette: 0.18,
            exposure: 2.5, baseLevel: 0.35, emissionGain: 0.85, pulseAmount: 0.1,
            bpm: 82, centerHole: 0.1, centerDark: 0.22, grain: 0.0018,
            color0: SIMD3(0.12, 1, 0.38), color1: SIMD3(0.78, 1, 0.22), color2: SIMD3(0.08, 0.78, 0.62),
            base: SIMD3(0.16, 0.035, 0.26), albumInfluence: 0
        )),
        make(.ember, "Ember Ring", cycles: true, album: 0.4, PresetParams(
            expansion: 0.07, rotation: 0.75, rotationInner: 0.4, kaleidoSpin: 0,
            warp: 0.16, warpFrequency: 3.4, warpSpeed: 0.36, radialWarp: 0.02,
            centerAmplitude: 0.012, goo: 0.1, folds: 1, kaleidoMix: 0,
            decayTau: 1.45, blur: 1.35, hueShift: 0.025, chroma: 2.2,
            frequency: 4.5, thickness: 0.016, radiusOffset: 0,
            count: 3, radius: 0.24, softness: 1, intensity: 1.25,
            sparkle: 1, saturation: 1.25, vignette: 0.62,
            exposure: 3.1, baseLevel: 0, emissionGain: 0.85, pulseAmount: 0.18,
            bpm: 102, centerHole: 0.12, centerDark: 1.8, grain: 0.0006,
            color0: SIMD3(1, 0.1, 0.04), color1: SIMD3(1, 0.42, 0.05), color2: SIMD3(1, 0.78, 0.28),
            base: SIMD3(0, 0, 0), albumInfluence: 0
        )),
        make(.tunnel, "Neon Tunnel", cycles: true, album: 0.5, PresetParams(
            expansion: 0.30, rotation: 0.1, rotationInner: 0.45, kaleidoSpin: 0.05,
            warp: 0.55, warpFrequency: 11, warpSpeed: 0.7, radialWarp: 0.04,
            centerAmplitude: 0, goo: 0.16, folds: 4, kaleidoMix: 1,
            decayTau: 0.55, blur: 0.55, hueShift: 0.3, chroma: 1.1,
            frequency: 14, thickness: 0.01, radiusOffset: 0,
            count: 4, radius: 0.3, softness: 2.4, intensity: 1.1,
            sparkle: 0.1, saturation: 1.4, vignette: 0.3,
            exposure: 2.5, baseLevel: 0, emissionGain: 0.9, pulseAmount: 0.16,
            bpm: 112, centerHole: 0.06, centerDark: 0.7, grain: 0.0009,
            color0: SIMD3(1, 0.05, 0.72), color1: SIMD3(0.15, 0.85, 1), color2: SIMD3(0.48, 0.18, 1),
            base: SIMD3(0.02, 0, 0.03), albumInfluence: 0
        )),
        make(.silk, "Liquid Silk", cycles: true, album: 0.55, PresetParams(
            expansion: 0.04, rotation: 0.07, rotationInner: 0.02, kaleidoSpin: 0.02,
            warp: 0.48, warpFrequency: 4.2, warpSpeed: 0.22, radialWarp: 0.03,
            centerAmplitude: 0.015, goo: 0.22, folds: 2, kaleidoMix: 0.92,
            decayTau: 0.9, blur: 1.05, hueShift: 0.06, chroma: 0.4,
            frequency: 3.2, thickness: 0.02, radiusOffset: 0,
            count: 2, radius: 0.2, softness: 1, intensity: 0.95,
            sparkle: 0, saturation: 1.22, vignette: 0.28,
            exposure: 2.3, baseLevel: 0.12, emissionGain: 0.75, pulseAmount: 0.08,
            bpm: 72, centerHole: 0.05, centerDark: 0.12, grain: 0.0016,
            color0: SIMD3(0.95, 0.18, 0.55), color1: SIMD3(1, 0.74, 0.32), color2: SIMD3(1, 0.38, 0.58),
            base: SIMD3(0.07, 0.015, 0.04), albumInfluence: 0
        )),
        make(.wheel, "Prism Wheel", cycles: true, album: 0.46, PresetParams(
            expansion: 0.13, rotation: 0.34, rotationInner: 0.12, kaleidoSpin: 0.12,
            warp: 0.28, warpFrequency: 7.5, warpSpeed: 0.4, radialWarp: 0.05,
            centerAmplitude: 0, goo: 0.12, folds: 12, kaleidoMix: 1,
            decayTau: 0.58, blur: 0.5, hueShift: 0.45, chroma: 0.7,
            frequency: 8, thickness: 0.0045, radiusOffset: 0,
            count: 12, radius: 0.40, softness: 1, intensity: 1.05,
            sparkle: 0.25, saturation: 1.38, vignette: 0.26,
            exposure: 2.5, baseLevel: 0, emissionGain: 0.85, pulseAmount: 0.12,
            bpm: 118, centerHole: 0.08, centerDark: 0.38, grain: 0.0022,
            color0: SIMD3(0.22, 0.42, 1), color1: SIMD3(0.75, 0.88, 1), color2: SIMD3(0.62, 0.18, 1),
            base: SIMD3(0.01, 0.01, 0.03), albumInfluence: 0
        )),
        make(.aurora, "Aurora", cycles: false, album: 0.4, PresetParams(
            expansion: 0.025, rotation: 0.015, rotationInner: 0, kaleidoSpin: 0,
            warp: 0.22, warpFrequency: 2.6, warpSpeed: 0.12, radialWarp: 0.01,
            centerAmplitude: 0.03, goo: 0.45, folds: 1, kaleidoMix: 0,
            decayTau: 1.35, blur: 1.6, hueShift: 0.04, chroma: 0.2,
            frequency: 2.4, thickness: 0.02, radiusOffset: 0,
            count: 1, radius: 0.2, softness: 1, intensity: 0.9,
            sparkle: 0, saturation: 1.18, vignette: 0.38,
            exposure: 1.9, baseLevel: 0.1, emissionGain: 0.65, pulseAmount: 0.05,
            bpm: 60, centerHole: 0, centerDark: 0.08, grain: 0.0012,
            color0: SIMD3(0.18, 0.95, 0.72), color1: SIMD3(0.22, 0.4, 1), color2: SIMD3(0.78, 0.28, 0.85),
            base: SIMD3(0.01, 0.02, 0.045), albumInfluence: 0
        )),
        make(.bloom, "Soft Bloom", cycles: false, album: 0.5, PresetParams(
            expansion: 0.035, rotation: 0.05, rotationInner: 0.02, kaleidoSpin: 0,
            warp: 0.16, warpFrequency: 2.2, warpSpeed: 0.16, radialWarp: 0.02,
            centerAmplitude: 0.02, goo: 0.32, folds: 1, kaleidoMix: 0,
            decayTau: 1.05, blur: 1.7, hueShift: 0.03, chroma: 0.25,
            frequency: 2, thickness: 0.02, radiusOffset: 0,
            count: 5, radius: 0.2, softness: 1, intensity: 1,
            sparkle: 0, saturation: 1.15, vignette: 0.34,
            exposure: 2.15, baseLevel: 0.06, emissionGain: 0.7, pulseAmount: 0.1,
            bpm: 68, centerHole: 0, centerDark: 0.05, grain: 0.001,
            color0: SIMD3(1, 0.42, 0.68), color1: SIMD3(1, 0.7, 0.42), color2: SIMD3(0.58, 0.48, 1),
            base: SIMD3(0.03, 0.01, 0.03), albumInfluence: 0
        )),
        make(.border, "Night Border", cycles: false, album: 0.48, PresetParams(
            expansion: 0.02, rotation: 0.05, rotationInner: 0, kaleidoSpin: 0,
            warp: 0.18, warpFrequency: 5, warpSpeed: 0.22, radialWarp: 0.02,
            centerAmplitude: 0, goo: 0.05, folds: 1, kaleidoMix: 0,
            decayTau: 0.8, blur: 0.9, hueShift: 0.07, chroma: 0.45,
            frequency: 6, thickness: 0.01, radiusOffset: 0,
            count: 1, radius: 0.62, softness: 1, intensity: 1.1,
            sparkle: 0.08, saturation: 1.3, vignette: 0.18,
            exposure: 2.7, baseLevel: 0, emissionGain: 0.6, pulseAmount: 0.1,
            bpm: 76, centerHole: 0.30, centerDark: 3.4, grain: 0.0003,
            color0: SIMD3(0.25, 0.45, 1), color1: SIMD3(0.68, 0.22, 1), color2: SIMD3(1, 0.32, 0.68),
            base: SIMD3(0, 0, 0), albumInfluence: 0
        )),
        make(.drift, "Slow Drift", cycles: false, album: 0.35, PresetParams(
            expansion: 0.02, rotation: 0.035, rotationInner: 0, kaleidoSpin: 0,
            warp: 0.12, warpFrequency: 1.8, warpSpeed: 0.1, radialWarp: 0.01,
            centerAmplitude: 0.025, goo: 0.18, folds: 1, kaleidoMix: 0,
            decayTau: 1.6, blur: 1.2, hueShift: 0.02, chroma: 0.15,
            frequency: 4.5, thickness: 0.02, radiusOffset: 0,
            count: 1, radius: 0.2, softness: 1, intensity: 1.1,
            sparkle: 1, saturation: 1.12, vignette: 0.42,
            exposure: 2.4, baseLevel: 0.04, emissionGain: 0.75, pulseAmount: 0.04,
            bpm: 64, centerHole: 0.05, centerDark: 0.15, grain: 0.0014,
            color0: SIMD3(0.75, 0.88, 1), color1: SIMD3(1, 0.86, 0.55), color2: SIMD3(0.35, 0.8, 0.75),
            base: SIMD3(0.008, 0.012, 0.028), albumInfluence: 0
        )),
        make(.scope, "Scope Trace", cycles: true, album: 0.48, PresetParams(
            expansion: 0.16, rotation: 0.42, rotationInner: 0.18, kaleidoSpin: 0.05,
            warp: 0.22, warpFrequency: 5.5, warpSpeed: 0.28, radialWarp: 0.04,
            centerAmplitude: 0, goo: 0.06, folds: 1, kaleidoMix: 0,
            decayTau: 0.78, blur: 0.45, hueShift: 0.08, chroma: 0.55,
            frequency: 6, thickness: 0.008, radiusOffset: 0,
            count: 5, radius: 0.3, softness: 1, intensity: 1.05,
            sparkle: 0.05, saturation: 1.4, vignette: 0.22,
            exposure: 2.45, baseLevel: 0, emissionGain: 0.95, pulseAmount: 0.12,
            bpm: 108, centerHole: 0.02, centerDark: 0.2, grain: 0.0005,
            color0: SIMD3(0.15, 0.95, 1), color1: SIMD3(1, 0.25, 0.75), color2: SIMD3(0.85, 0.95, 1),
            base: SIMD3(0.01, 0.012, 0.03), albumInfluence: 0
        )),
        make(.mirror, "Mirror Hall", cycles: true, album: 0.5, PresetParams(
            expansion: 0.18, rotation: 0.22, rotationInner: 0.08, kaleidoSpin: 0.06,
            warp: 0.2, warpFrequency: 6.0, warpSpeed: 0.26, radialWarp: 0.03,
            centerAmplitude: 0, goo: 0.05, folds: 6, kaleidoMix: 1,
            decayTau: 0.64, blur: 0.4, hueShift: 0.12, chroma: 0.6,
            frequency: 6, thickness: 0.007, radiusOffset: 0,
            count: 6, radius: 0.28, softness: 1, intensity: 1.05,
            sparkle: 0.08, saturation: 1.42, vignette: 0.24,
            exposure: 2.5, baseLevel: 0, emissionGain: 0.9, pulseAmount: 0.12,
            bpm: 100, centerHole: 0.04, centerDark: 0.35, grain: 0.0004,
            color0: SIMD3(1, 0.82, 0.25), color1: SIMD3(0.62, 0.28, 1), color2: SIMD3(0.75, 0.95, 1),
            base: SIMD3(0.02, 0.01, 0.03), albumInfluence: 0
        )),
        make(.plasma, "Plasma Veil", cycles: true, album: 0.46, PresetParams(
            expansion: 0.08, rotation: 0.12, rotationInner: 0.04, kaleidoSpin: 0.02,
            warp: 0.34, warpFrequency: 4.4, warpSpeed: 0.22, radialWarp: 0.03,
            centerAmplitude: 0.01, goo: 0.12, folds: 1, kaleidoMix: 0,
            decayTau: 0.72, blur: 0.7, hueShift: 0.1, chroma: 0.45,
            frequency: 5, thickness: 0.01, radiusOffset: 0,
            count: 1, radius: 0.2, softness: 1, intensity: 1,
            sparkle: 0, saturation: 1.48, vignette: 0.2,
            exposure: 2.4, baseLevel: 0, emissionGain: 0.9, pulseAmount: 0.1,
            bpm: 96, centerHole: 0, centerDark: 0.08, grain: 0.0006,
            color0: SIMD3(1, 0.1, 0.65), color1: SIMD3(0.15, 0.9, 1), color2: SIMD3(1, 0.92, 0.2),
            base: SIMD3(0.015, 0.005, 0.02), albumInfluence: 0
        )),
        make(.warpStars, "Warp Stars", cycles: true, album: 0.4, PresetParams(
            expansion: 0.7, rotation: 0.05, rotationInner: 0.15, kaleidoSpin: 0,
            warp: 0.08, warpFrequency: 2.2, warpSpeed: 0.16, radialWarp: 0.01,
            centerAmplitude: 0, goo: 0.02, folds: 1, kaleidoMix: 0,
            decayTau: 0.48, blur: 0.35, hueShift: 0.04, chroma: 0.35,
            frequency: 4, thickness: 0.01, radiusOffset: 0,
            count: 1, radius: 0.2, softness: 1, intensity: 1.1,
            sparkle: 0.4, saturation: 1.2, vignette: 0.4,
            exposure: 2.7, baseLevel: 0, emissionGain: 0.85, pulseAmount: 0.16,
            bpm: 124, centerHole: 0.03, centerDark: 0.5, grain: 0.0003,
            color0: SIMD3(0.75, 0.88, 1), color1: SIMD3(1, 0.95, 0.8), color2: SIMD3(0.45, 0.6, 1),
            base: SIMD3(0, 0, 0.01), albumInfluence: 0
        )),
        make(.well, "Fractal Well", cycles: true, album: 0.48, PresetParams(
            expansion: 0.38, rotation: 0.16, rotationInner: 0.35, kaleidoSpin: 0.04,
            warp: 0.18, warpFrequency: 8.0, warpSpeed: 0.4, radialWarp: 0.04,
            centerAmplitude: 0, goo: 0.06, folds: 4, kaleidoMix: 0.85,
            decayTau: 0.58, blur: 0.4, hueShift: 0.16, chroma: 0.8,
            frequency: 9, thickness: 0.008, radiusOffset: 0,
            count: 4, radius: 0.25, softness: 1.4, intensity: 1.05,
            sparkle: 0.06, saturation: 1.4, vignette: 0.32,
            exposure: 2.55, baseLevel: 0, emissionGain: 0.92, pulseAmount: 0.14,
            bpm: 118, centerHole: 0.05, centerDark: 0.85, grain: 0.0005,
            color0: SIMD3(0.55, 0.15, 1), color1: SIMD3(1, 0.2, 0.55), color2: SIMD3(0.15, 0.9, 0.85),
            base: SIMD3(0.01, 0, 0.02), albumInfluence: 0
        )),
        make(.bleed, "Color Bleed", cycles: true, album: 0.55, PresetParams(
            expansion: 0.05, rotation: 0.28, rotationInner: 0.06, kaleidoSpin: 0.03,
            warp: 0.26, warpFrequency: 3.2, warpSpeed: 0.16, radialWarp: 0.02,
            centerAmplitude: 0.02, goo: 0.2, folds: 1, kaleidoMix: 0,
            decayTau: 1.35, blur: 1.45, hueShift: 0.07, chroma: 0.35,
            frequency: 3, thickness: 0.02, radiusOffset: 0,
            count: 3, radius: 0.2, softness: 1, intensity: 0.9,
            sparkle: 0, saturation: 1.3, vignette: 0.26,
            exposure: 2.2, baseLevel: 0.04, emissionGain: 0.75, pulseAmount: 0.08,
            bpm: 84, centerHole: 0, centerDark: 0.06, grain: 0.0012,
            color0: SIMD3(1, 0.12, 0.28), color1: SIMD3(1, 0.48, 0.12), color2: SIMD3(0.95, 0.2, 0.7),
            base: SIMD3(0.03, 0.005, 0.015), albumInfluence: 0
        )),
        make(.vortex, "Vortex Eye", cycles: true, album: 0.46, PresetParams(
            expansion: 0.22, rotation: 0.62, rotationInner: 0.55, kaleidoSpin: 0.04,
            warp: 0.3, warpFrequency: 6.5, warpSpeed: 0.38, radialWarp: 0.06,
            centerAmplitude: 0, goo: 0.1, folds: 1, kaleidoMix: 0,
            decayTau: 0.7, blur: 0.55, hueShift: 0.1, chroma: 0.65,
            frequency: 6, thickness: 0.01, radiusOffset: 0,
            count: 4, radius: 0.22, softness: 1, intensity: 1.05,
            sparkle: 0.04, saturation: 1.38, vignette: 0.28,
            exposure: 2.5, baseLevel: 0, emissionGain: 0.95, pulseAmount: 0.15,
            bpm: 110, centerHole: 0.035, centerDark: 0.9, grain: 0.00045,
            color0: SIMD3(0.2, 0.55, 1), color1: SIMD3(0.85, 0.92, 1), color2: SIMD3(0.35, 0.15, 0.95),
            base: SIMD3(0.005, 0.01, 0.03), albumInfluence: 0
        )),
        make(.mesh, "Mesh Tide", cycles: true, album: 0.44, PresetParams(
            expansion: 0.1, rotation: 0.08, rotationInner: 0.02, kaleidoSpin: 0,
            warp: 0.42, warpFrequency: 5.2, warpSpeed: 0.3, radialWarp: 0.04,
            centerAmplitude: 0.012, goo: 0.16, folds: 1, kaleidoMix: 0,
            decayTau: 0.66, blur: 0.5, hueShift: 0.09, chroma: 0.4,
            frequency: 8, thickness: 0.008, radiusOffset: 0,
            count: 1, radius: 0.2, softness: 1, intensity: 1,
            sparkle: 0, saturation: 1.35, vignette: 0.18,
            exposure: 2.45, baseLevel: 0, emissionGain: 0.85, pulseAmount: 0.11,
            bpm: 104, centerHole: 0, centerDark: 0.05, grain: 0.0005,
            color0: SIMD3(0.2, 1, 0.55), color1: SIMD3(0.95, 1, 0.3), color2: SIMD3(0.2, 0.85, 1),
            base: SIMD3(0.005, 0.015, 0.012), albumInfluence: 0
        )),
        make(.water, "Water Glass", cycles: true, album: 0.5, PresetParams(
            expansion: 0.06, rotation: 0.04, rotationInner: 0.02, kaleidoSpin: 0,
            warp: 0.2, warpFrequency: 3.6, warpSpeed: 0.18, radialWarp: 0.025,
            centerAmplitude: 0.018, goo: 0.14, folds: 1, kaleidoMix: 0,
            decayTau: 0.88, blur: 0.85, hueShift: 0.05, chroma: 0.3,
            frequency: 8, thickness: 0.008, radiusOffset: 0,
            count: 1, radius: 0.2, softness: 1, intensity: 1,
            sparkle: 0.12, saturation: 1.28, vignette: 0.22,
            exposure: 2.35, baseLevel: 0.02, emissionGain: 0.85, pulseAmount: 0.1,
            bpm: 90, centerHole: 0, centerDark: 0.05, grain: 0.0007,
            color0: SIMD3(0.1, 0.35, 0.95), color1: SIMD3(0.35, 0.95, 0.9), color2: SIMD3(0.85, 0.95, 1),
            base: SIMD3(0.005, 0.012, 0.03), albumInfluence: 0
        )),
        make(.flame, "Flame Lift", cycles: true, album: 0.42, PresetParams(
            expansion: 0.04, rotation: 0.06, rotationInner: 0.02, kaleidoSpin: 0,
            warp: 0.24, warpFrequency: 3.8, warpSpeed: 0.32, radialWarp: 0.02,
            centerAmplitude: 0.01, goo: 0.18, folds: 1, kaleidoMix: 0,
            decayTau: 0.95, blur: 1.05, hueShift: 0.03, chroma: 0.5,
            frequency: 4, thickness: 0.02, radiusOffset: 0,
            count: 4, radius: 0.2, softness: 1, intensity: 1.05,
            sparkle: 0.2, saturation: 1.32, vignette: 0.36,
            exposure: 2.55, baseLevel: 0, emissionGain: 0.9, pulseAmount: 0.14,
            bpm: 98, centerHole: 0.02, centerDark: 0.25, grain: 0.0008,
            color0: SIMD3(0.85, 0.05, 0.02), color1: SIMD3(1, 0.42, 0.05), color2: SIMD3(1, 0.86, 0.28),
            base: SIMD3(0.01, 0, 0), albumInfluence: 0
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
}
