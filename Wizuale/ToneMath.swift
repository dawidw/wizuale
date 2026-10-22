import Foundation

/// Sanity reference for the dark MilkDrop tone path (implemented in `Shaders.metal`
/// and smoothed in `VisualRenderer.noteMeanLuma`).
///
/// Feedback (linear `rgba16Float`): per-frame keep ≈ 0.90–0.96, emit via `max`
/// with peak cap, buffer luma ≤ 0.75.
///
/// Present (`bgra8Unorm`, linear in — no shader `pow(1/2.2)`): saturation boost,
/// hue-preserving peak cap 0.92, frame gain = min(presetExposure, 1) × smoothedGain
/// where smoothedGain eases toward min(1, 0.25 / meanLuma) over ~0.2 s.
enum ToneMath {
    static let feedbackLumaCap: Float = 0.75
    static let presentPeakCap: Float = 0.92
    static let presentMeanTarget: Float = 0.25
    static let outputGainSmoothSeconds: Float = 0.2
}
