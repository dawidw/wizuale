import SwiftUI

/// TV overlay toggled from Wizuale Mic — PCM buffer depth, levels, and beat features.
struct MicAudioDebugOverlay: View {
    var drive: MicDrive
    var metrics: ProjectMAudioHub.Metrics
    var latencyMs: Int

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
            row("Onset", String(format: "%.2f  Bass %.2f", drive.onset, drive.bass))
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
