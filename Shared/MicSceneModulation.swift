import Foundation

/// Per-frame scene path after UDP → TV sliders (for DEBUG overlay and tests).
struct SceneModulationTrace: Sendable, Equatable {
    var beatStrengthPercent: Int
    var sceneIntensityPermille: Int
    var intensityMultiplier: Float
    var strengthScale: Float
    var kickEnvelope: Float
    var kickSensitivityBoost: Float
    var continuousSensitivityBoost: Float
    var projectMBeatSensitivity: Float
    var pcmKickMix: Float
    var tsunamiMaxDisplacement: Float
}

enum MicSceneModulation {
    /// Maps Mic→TV slider values to libprojectM sensitivity and PCM kick mix.
    static func compute(
        baseBeatSensitivity: Float,
        kickEnvelope: Float,
        beatStrengthPercent: Int,
        sceneIntensityPermille: Int,
        bass: Float
    ) -> (trace: SceneModulationTrace, projectMSensitivity: Float, pcmKickMix: Float) {
        let permille = MicTuning.clampSceneIntensity(sceneIntensityPermille)
        let beatPct = MicTuning.clampBeatStrength(beatStrengthPercent)
        let intensity = MicTuning.sceneIntensityMultiplier(permille)
        let strength = Float(beatPct) / 100
        let env = min(max(kickEnvelope, 0), 1.4)

        let kickBoost = env * MicTuning.scenePunchSensitivityBoostBaseline * strength * intensity
        let continuousBoost = min(max(bass, 0), 2.8)
            * MicTuning.sceneContinuousSensitivityBaseline
            * intensity
        let projectMSens = MicTuning.clampSceneBeatSensitivity(
            base: baseBeatSensitivity,
            kickBoost: kickBoost,
            continuousBoost: continuousBoost
        )
        let pcmMix = env * MicTuning.scenePunchPCMSMixBaseline * strength * intensity
        let tsunamiDisp = MicTuning.kickWaveEffectiveDisplacement(envelope: env, strengthScale: strength)

        let trace = SceneModulationTrace(
            beatStrengthPercent: beatPct,
            sceneIntensityPermille: permille,
            intensityMultiplier: intensity,
            strengthScale: strength,
            kickEnvelope: env,
            kickSensitivityBoost: kickBoost,
            continuousSensitivityBoost: continuousBoost,
            projectMBeatSensitivity: projectMSens,
            pcmKickMix: pcmMix,
            tsunamiMaxDisplacement: tsunamiDisp
        )
        return (trace, projectMSens, pcmMix)
    }
}

#if DEBUG
/// Mirrors `ProjectMKickWaveCompositor` fragment displacement (for offline PNG checks).
enum KickWaveDisplacementPreview {
    static func radialDisplacement(
        u: Float,
        v: Float,
        aspect: Float,
        envelope: Float,
        kickAge: Float,
        strengthScale: Float
    ) -> Float {
        var px = u - 0.5
        var py = v - 0.5
        px *= aspect
        let r = sqrt(px * px + py * py)
        let phase = kickAge * MicTuning.kickWavePhaseSpeed
        var ring = sin(r * MicTuning.kickWaveRingFrequency - phase)
        ring *= exp(-r * MicTuning.kickWaveRingFalloff)
        ring *= envelope * strengthScale
        return ring * MicTuning.kickWaveShaderMaxDisplacement(strengthScale: strengthScale)
    }
}
#endif
