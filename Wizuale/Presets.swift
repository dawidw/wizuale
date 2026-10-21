import simd

/// Draw styles in Shaders.metal. The raw value is the `mode` the shader branches on.
enum VisualMode: Int, CaseIterable, Identifiable {
    case tunnelVision = 0
    case plasmaDrift = 1
    case spectrumSpiral = 2
    case kaleidoBass = 3
    case starburst = 4
    case waveformGlow = 5
    case liquidMirror = 6
    case electricSheep = 7
    case fractalTunnel = 8
    case spectrumBars = 9
    case vortexPulse = 10
    case hueWheel = 11

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
        make(.tunnelVision, "Tunnel Vision", cycles: true, album: 0.48, classic(
            expansion: 0.38, rotation: 0.14, rotationInner: 0.42, kaleidoSpin: 0.04,
            warp: 0.52, warpFrequency: 12, warpSpeed: 0.72, radialWarp: 0.05,
            goo: 0.14, folds: 6, kaleidoMix: 0.85, decayTau: 0.58, blur: 0.55,
            hueShift: 0.28, chroma: 0.9, frequency: 14, thickness: 0.009,
            count: 6, radius: 0.28, softness: 2.2, intensity: 1.05,
            sparkle: 0.08, saturation: 1.42, exposure: 2.45, pulseAmount: 0.16, bpm: 118,
            centerHole: 0.05, centerDark: 0.65, grain: 0.0007,
            c0: SIMD3(1, 0.08, 0.68), c1: SIMD3(0.12, 0.88, 1), c2: SIMD3(0.55, 0.15, 1)
        )),
        make(.plasmaDrift, "Plasma Drift", cycles: true, album: 0.46, classic(
            expansion: 0.10, rotation: 0.18, rotationInner: 0.05, kaleidoSpin: 0.03,
            warp: 0.36, warpFrequency: 4.8, warpSpeed: 0.26, radialWarp: 0.04,
            goo: 0.14, folds: 1, kaleidoMix: 0, decayTau: 0.68, blur: 0.65,
            hueShift: 0.14, chroma: 0.55, frequency: 5.5, thickness: 0.01,
            count: 1, radius: 0.2, softness: 1, intensity: 1,
            sparkle: 0, saturation: 1.48, exposure: 2.35, pulseAmount: 0.11, bpm: 100,
            centerHole: 0, centerDark: 0.1, grain: 0.0006,
            c0: SIMD3(1, 0.12, 0.55), c1: SIMD3(0.18, 0.95, 1), c2: SIMD3(1, 0.9, 0.22)
        )),
        make(.spectrumSpiral, "Spectrum Spiral", cycles: true, album: 0.5, classic(
            expansion: 0.44, rotation: 0.58, rotationInner: 0.22, kaleidoSpin: 0.06,
            warp: 0.26, warpFrequency: 7.2, warpSpeed: 0.38, radialWarp: 0.05,
            goo: 0.1, folds: 1, kaleidoMix: 0, decayTau: 0.62, blur: 0.48,
            hueShift: 0.2, chroma: 0.75, frequency: 8, thickness: 0.009,
            count: 8, radius: 0.34, softness: 1.1, intensity: 1.02,
            sparkle: 0.06, saturation: 1.45, exposure: 2.5, pulseAmount: 0.14, bpm: 104,
            centerHole: 0.04, centerDark: 0.35, grain: 0.0005,
            c0: SIMD3(1, 0.2, 0.55), c1: SIMD3(1, 0.82, 0.15), c2: SIMD3(0.15, 0.95, 0.82)
        )),
        make(.kaleidoBass, "Kaleido Bass", cycles: true, album: 0.5, classic(
            expansion: 0.2, rotation: 0.28, rotationInner: 0.1, kaleidoSpin: 0.1,
            warp: 0.22, warpFrequency: 6.2, warpSpeed: 0.3, radialWarp: 0.04,
            goo: 0.08, folds: 8, kaleidoMix: 1, decayTau: 0.6, blur: 0.42,
            hueShift: 0.16, chroma: 0.65, frequency: 6, thickness: 0.007,
            count: 8, radius: 0.3, softness: 1, intensity: 1.05,
            sparkle: 0.1, saturation: 1.4, exposure: 2.48, pulseAmount: 0.13, bpm: 108,
            centerHole: 0.05, centerDark: 0.4, grain: 0.00045,
            c0: SIMD3(1, 0.78, 0.2), c1: SIMD3(0.55, 0.2, 1), c2: SIMD3(0.75, 0.95, 1)
        )),
        make(.starburst, "Starburst", cycles: true, album: 0.42, classic(
            expansion: 0.72, rotation: 0.06, rotationInner: 0.18, kaleidoSpin: 0,
            warp: 0.1, warpFrequency: 2.4, warpSpeed: 0.18, radialWarp: 0.02,
            goo: 0.03, folds: 1, kaleidoMix: 0, decayTau: 0.5, blur: 0.38,
            hueShift: 0.06, chroma: 0.4, frequency: 4, thickness: 0.01,
            count: 1, radius: 0.2, softness: 1, intensity: 1.08,
            sparkle: 0.45, saturation: 1.22, exposure: 2.55, pulseAmount: 0.17, bpm: 126,
            centerHole: 0.03, centerDark: 0.55, grain: 0.00035,
            c0: SIMD3(0.8, 0.9, 1), c1: SIMD3(1, 0.95, 0.75), c2: SIMD3(0.45, 0.65, 1)
        )),
        make(.waveformGlow, "Waveform Glow", cycles: true, album: 0.48, classic(
            expansion: 0.14, rotation: 0.35, rotationInner: 0.12, kaleidoSpin: 0.02,
            warp: 0.2, warpFrequency: 5.5, warpSpeed: 0.3, radialWarp: 0.03,
            goo: 0.06, folds: 1, kaleidoMix: 0, decayTau: 0.72, blur: 0.42,
            hueShift: 0.1, chroma: 0.55, frequency: 7, thickness: 0.006,
            count: 5, radius: 0.32, softness: 1, intensity: 1.05,
            sparkle: 0.05, saturation: 1.38, exposure: 2.42, pulseAmount: 0.12, bpm: 112,
            centerHole: 0.02, centerDark: 0.22, grain: 0.0005,
            c0: SIMD3(0.15, 0.95, 1), c1: SIMD3(1, 0.28, 0.72), c2: SIMD3(0.85, 0.95, 1)
        )),
        make(.liquidMirror, "Liquid Mirror", cycles: true, album: 0.52, classic(
            expansion: 0.06, rotation: 0.1, rotationInner: 0.04, kaleidoSpin: 0.04,
            warp: 0.46, warpFrequency: 4.5, warpSpeed: 0.24, radialWarp: 0.035,
            goo: 0.22, folds: 2, kaleidoMix: 0.9, decayTau: 0.82, blur: 1.0,
            hueShift: 0.08, chroma: 0.45, frequency: 3.6, thickness: 0.018,
            count: 2, radius: 0.2, softness: 1, intensity: 0.95,
            sparkle: 0, saturation: 1.28, exposure: 2.28, pulseAmount: 0.09, bpm: 88,
            centerHole: 0.04, centerDark: 0.12, grain: 0.0014,
            c0: SIMD3(0.95, 0.22, 0.58), c1: SIMD3(1, 0.72, 0.32), c2: SIMD3(0.35, 0.85, 1)
        )),
        make(.electricSheep, "Electric Sheep", cycles: true, album: 0.44, classic(
            expansion: 0.05, rotation: 0.12, rotationInner: 0.03, kaleidoSpin: 0.02,
            warp: 0.18, warpFrequency: 2.2, warpSpeed: 0.14, radialWarp: 0.02,
            goo: 0.12, folds: 1, kaleidoMix: 0, decayTau: 1.1, blur: 1.15,
            hueShift: 0.05, chroma: 0.35, frequency: 3, thickness: 0.02,
            count: 1, radius: 0.2, softness: 1, intensity: 0.92,
            sparkle: 0.35, saturation: 1.25, exposure: 2.3, pulseAmount: 0.08, bpm: 92,
            centerHole: 0.03, centerDark: 0.15, grain: 0.0012,
            c0: SIMD3(0.55, 0.95, 0.45), c1: SIMD3(0.85, 0.35, 1), c2: SIMD3(1, 0.85, 0.35)
        )),
        make(.fractalTunnel, "Fractal Tunnel", cycles: true, album: 0.48, classic(
            expansion: 0.4, rotation: 0.18, rotationInner: 0.38, kaleidoSpin: 0.05,
            warp: 0.2, warpFrequency: 8.5, warpSpeed: 0.42, radialWarp: 0.05,
            goo: 0.07, folds: 4, kaleidoMix: 0.8, decayTau: 0.56, blur: 0.42,
            hueShift: 0.18, chroma: 0.85, frequency: 9, thickness: 0.008,
            count: 4, radius: 0.26, softness: 1.35, intensity: 1.04,
            sparkle: 0.06, saturation: 1.38, exposure: 2.5, pulseAmount: 0.15, bpm: 116,
            centerHole: 0.05, centerDark: 0.8, grain: 0.0005,
            c0: SIMD3(0.5, 0.15, 1), c1: SIMD3(1, 0.22, 0.55), c2: SIMD3(0.15, 0.9, 0.82)
        )),
        make(.spectrumBars, "Spectrum Bars", cycles: true, album: 0.5, classic(
            expansion: 0.12, rotation: 0.08, rotationInner: 0.04, kaleidoSpin: 0,
            warp: 0.16, warpFrequency: 4, warpSpeed: 0.22, radialWarp: 0.02,
            goo: 0.05, folds: 1, kaleidoMix: 0, decayTau: 0.74, blur: 0.4,
            hueShift: 0.12, chroma: 0.5, frequency: 5, thickness: 0.01,
            count: 16, radius: 0.2, softness: 1, intensity: 1.02,
            sparkle: 0.04, saturation: 1.42, exposure: 2.4, pulseAmount: 0.12, bpm: 110,
            centerHole: 0, centerDark: 0.08, grain: 0.00055,
            c0: SIMD3(0.2, 1, 0.45), c1: SIMD3(1, 0.85, 0.2), c2: SIMD3(0.2, 0.75, 1)
        )),
        make(.vortexPulse, "Vortex Pulse", cycles: true, album: 0.46, classic(
            expansion: 0.24, rotation: 0.68, rotationInner: 0.58, kaleidoSpin: 0.04,
            warp: 0.32, warpFrequency: 6.8, warpSpeed: 0.4, radialWarp: 0.06,
            goo: 0.1, folds: 1, kaleidoMix: 0, decayTau: 0.66, blur: 0.52,
            hueShift: 0.12, chroma: 0.7, frequency: 6, thickness: 0.01,
            count: 4, radius: 0.22, softness: 1, intensity: 1.04,
            sparkle: 0.05, saturation: 1.36, exposure: 2.45, pulseAmount: 0.15, bpm: 114,
            centerHole: 0.035, centerDark: 0.85, grain: 0.00045,
            c0: SIMD3(0.22, 0.55, 1), c1: SIMD3(0.85, 0.92, 1), c2: SIMD3(0.38, 0.15, 0.95)
        )),
        make(.hueWheel, "Hue Wheel", cycles: true, album: 0.46, classic(
            expansion: 0.15, rotation: 0.38, rotationInner: 0.14, kaleidoSpin: 0.14,
            warp: 0.26, warpFrequency: 7.8, warpSpeed: 0.42, radialWarp: 0.05,
            goo: 0.11, folds: 12, kaleidoMix: 1, decayTau: 0.58, blur: 0.48,
            hueShift: 0.42, chroma: 0.75, frequency: 8, thickness: 0.0045,
            count: 12, radius: 0.42, softness: 1, intensity: 1.02,
            sparkle: 0.22, saturation: 1.4, exposure: 2.45, pulseAmount: 0.13, bpm: 120,
            centerHole: 0.07, centerDark: 0.35, grain: 0.002,
            c0: SIMD3(0.22, 0.42, 1), c1: SIMD3(0.75, 0.88, 1), c2: SIMD3(0.62, 0.18, 1)
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
            exposure: exposure, baseLevel: 0, emissionGain: 0.9, pulseAmount: pulseAmount,
            bpm: bpm, centerHole: centerHole, centerDark: centerDark, grain: grain,
            color0: c0, color1: c1, color2: c2,
            base: SIMD3(0.008, 0.006, 0.014), albumInfluence: 0
        )
    }
}
