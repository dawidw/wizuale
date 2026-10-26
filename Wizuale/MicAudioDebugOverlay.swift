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
            row("FIFO", String(format: "%.0f ms (%d smp)", metrics.fifoMs, metrics.fifoSamples))
            row("Chunk", "\(metrics.lastChunk) smp/frame")
            row("RMS", String(format: "%.3f  AGC %.1f×", metrics.rms, metrics.agcGain))
            row("Latency", "\(latencyMs) ms (slider)")
            row("Onset", String(format: "%.2f  Bass %.2f", drive.onset, drive.bass))
            row("Mid/Hi", String(format: "%.2f / %.2f", drive.mid, drive.high))
            row("Presence", String(format: "%.2f  Flux %.2f", drive.presence, drive.flux))
            row("Accent", String(format: "%.2f", metrics.accentOnset))
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
        case .idle: return "IDLE (waiting)"
        case .none: return "NONE (mic off)"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 72, alignment: .leading)
            Text(value)
        }
    }
}
