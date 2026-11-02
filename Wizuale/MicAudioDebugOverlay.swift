import SwiftUI

/// TV overlay toggled from Wizuale Mic — PCM buffer depth, levels, and beat features.
struct MicAudioDebugOverlay: View {
    var drive: MicDrive
    var metrics: ProjectMAudioHub.Metrics
    var latencyMs: Int
    var beatStrength: Int
    var sceneIntensity: Int
    var punchesPerMinute: Int
    var kickEnvelope: Float
    var kickFlash: Bool
    var lastKickPeak: Float
    var detectionThreshold: Float
    var testSyntheticKick: Bool
    var phoneSensitivity: Float
    var modulation: SceneModulationTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUDIO DEBUG")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            row("Source", sourceLabel)
            row("TV mic", metrics.micSource.title)
            row("PCM rx", metrics.streamLive ? "live" : "stale/none")
            row("Wi‑Fi feats", drive.presence > 0.12 ? "live" : "off")
            row("PCM/s", String(format: "%.0f", metrics.pcmPacketsPerSec))
            row("Gap ms", String(format: "avg %.0f  max %.0f", metrics.gapAvgMs, metrics.gapMaxMs))
            row("FIFO", String(format: "%.0f ms (%d smp)", metrics.fifoMs, metrics.fifoSamples))
            row("Underruns", "\(metrics.underrunTotal)")
            row("Chunk", "\(metrics.lastChunk) smp/frame")
            row("PCM in", String(format: "%.4f", metrics.pcmInRms))
            row("RMS", String(format: "%.3f  AGC %.1f×", metrics.rms, metrics.agcGain))
            row("projectM", String(format: "%.0f smp/s", metrics.projectMFeedSps))
            row("Latency", "\(latencyMs) ms (slider)")
            row("Feat age", String(format: "%.0f ms", drive.featureAgeMs))
            row("Onset", String(format: "%.2f  Bass %.2f", drive.onset, drive.bass))
            row(
                "Próg / czułość",
                String(format: "%.2f  sens %.2f×", detectionThreshold, phoneSensitivity)
            )
            row(
                "Detekcja bitu",
                String(format: "%.2f/s  ~%d bpm", Float(punchesPerMinute) / 60, punchesPerMinute)
            )
            row(
                "Kick env",
                String(
                    format: "%.2f  %@  szczyt %.2f  Siła %d%%",
                    kickEnvelope,
                    kickFlash ? "ONSET" : "—",
                    lastKickPeak,
                    beatStrength
                )
            )
            row("Test kick", testSyntheticKick ? "ON (500 ms)" : "off")
            row(
                "Scene punch",
                String(format: "PCM %.2f", metrics.scenePunch)
            )
            row("Intensywność", MicTuning.formatSceneIntensity(sceneIntensity))
            row(
                "RX suwaki",
                String(
                    format: "Siła %d%%  ‰ %d",
                    modulation.beatStrengthPercent,
                    modulation.sceneIntensityPermille
                )
            )
            row(
                "Mnożniki",
                String(
                    format: "N %.1f×  siła %.2f  env %.2f",
                    modulation.intensityMultiplier,
                    modulation.strengthScale,
                    modulation.kickEnvelope
                )
            )
            row(
                "→ projectM",
                String(
                    format: "sens %.2f  kick+%.2f  cont+%.2f",
                    modulation.projectMBeatSensitivity,
                    modulation.kickSensitivityBoost,
                    modulation.continuousSensitivityBoost
                )
            )
            row(
                "Mix bas/kick",
                String(
                    format: "cont/kick %.1f  PCM %.2f  UV %.3f",
                    modulation.continuousSensitivityBoost
                        / max(modulation.kickSensitivityBoost, 0.001),
                    modulation.pcmKickMix,
                    modulation.tsunamiMaxDisplacement
                )
            )
            row(
                "Tsunami UV",
                String(format: "peak %.3f  PCM mix %.2f", modulation.tsunamiMaxDisplacement, modulation.pcmKickMix)
            )
            row("Mid/Hi", String(format: "%.2f / %.2f", drive.mid, drive.high))
            row("Presence", String(format: "%.2f  Flux %.2f", drive.presence, drive.flux))
            if metrics.micSource == .phone && drive.presence > 0.12 && !metrics.streamLive {
                row("Anomaly", "feats without PCM")
            }
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.92))
        .padding(14)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 48)
        .padding(.top, 48)
    }

    private var sourceLabel: String {
        switch metrics.feedState {
        case .phonePCM: return "PHONE PCM"
        case .continuityPCM: return "CONTINUITY PCM"
        case .fallback: return "FALLBACK (silence)"
        case .idle: return "IDLE (prime)"
        case .none: return "NONE (mic off)"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 80, alignment: .leading)
            Text(value)
        }
    }
}
