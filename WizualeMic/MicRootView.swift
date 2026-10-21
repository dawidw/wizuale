import SwiftUI
import UIKit

/// Big start button, who the phone is sending to, and a live level.
struct MicRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var mic = MicCapture()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text("WIZUALE MIC")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.55))

                Text(headline)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(mic.status)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                meter(title: "Level", value: mic.level)
                meter(title: "Bass", value: mic.bassLevel)

                Spacer(minLength: 12)

                Button(action: { mic.toggle() }) {
                    Text(mic.running ? "Stop" : "Start")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(mic.running ? Color.white.opacity(0.14) : Color.white)
                        .foregroundStyle(mic.running ? Color.white : Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                mic.stop()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var headline: String {
        if mic.linked, !mic.tvName.isEmpty { return mic.tvName }
        if mic.running { return "Looking for Apple TV" }
        return "Ready"
    }

    private func meter(title: String, value: Float) -> some View {
        let amount = CGFloat(min(max(value, 0), 1))
        return VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * amount)
                }
            }
            .frame(height: 18)
        }
    }
}
