import SwiftUI
import UIKit

/// Big start button, whether the TV app has answered, and a preset strip.
struct MicRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var mic = MicCapture()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("WIZUALE MIC")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.55))

                    HStack(alignment: .center, spacing: 10) {
                        if mic.running {
                            Circle()
                                .fill(mic.linked ? Color.green : Color.white.opacity(0.28))
                                .frame(width: 12, height: 12)
                        }
                        Text(headline)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Text(mic.status)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    meter(title: "Level", value: mic.level)
                    meter(title: "Bass", value: mic.bassLevel)
                    hitSlider
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 8)

                PresetStrip(
                    active: mic.activePreset,
                    cycling: mic.cycling,
                    known: mic.pictureKnown
                ) { choice in
                    mic.selectPreset(choice)
                }

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
                .padding(.horizontal, 28)
            }
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
        if !mic.running { return "Ready" }
        if mic.linked {
            let name = mic.tvName.isEmpty ? "Apple TV" : mic.tvName
            return "Connected to \(name)"
        }
        return "Searching for Apple TV…"
    }

    private var hitSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HIT")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.1f×", mic.sensitivity))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(value: $mic.sensitivity, in: 0.5...2.0)
                .tint(.white)
        }
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
