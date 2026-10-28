import SwiftUI

/// Visible when AUDIO DEBUG is on — corner bars prove beat/PCM reach projectM (no full-screen flash).
struct BeatTestOverlay: View {
    var drive: MicDrive
    var metrics: ProjectMAudioHub.Metrics
    var punchFlash: Bool = false

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("BEAT TEST")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.7))
                    Circle()
                        .fill(Color(red: 0.45, green: 0.95, blue: 0.62))
                        .frame(width: 10, height: 10)
                        .opacity(beatIndicatorOpacity)
                }
                HStack(alignment: .bottom, spacing: 14) {
                    bar(label: "PCM", level: CGFloat(min(metrics.rms * 1.4, 1)))
                    bar(label: "BASS", level: CGFloat(min(drive.bass / 2.5, 1)))
                    bar(label: "KICK", level: CGFloat(min(drive.onset / 2.0, 1)))
                }
                Text(String(format: "→ projectM %.0f smp/s", metrics.projectMFeedSps))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Text(String(format: "RMS %.3f  onset %.2f", metrics.rms, drive.onset))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(12)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.trailing, 48)
            .padding(.top, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

    private var beatIndicatorOpacity: Double {
        if punchFlash { return 1 }
        let hit = max(drive.onset / 2.2, drive.bass * 0.22)
        return Double(min(max(hit, 0.12), 1))
    }

    private func bar(label: String, level: CGFloat) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.12))
                    .frame(width: 22, height: 100)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.92))
                    .frame(width: 22, height: max(4, 100 * level))
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
