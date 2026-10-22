import SwiftUI
import UIKit

/// Big start button, whether the TV app has answered, sensitivity, latency, and a preset strip.
struct MicRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var mic = MicCapture()
    @State private var dropPressing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
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
                        sensitivitySlider
                        latencySlider
                        autoCycleControls
                        calibrateControl
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    PresetStrip(
                        active: mic.activePreset,
                        cycling: mic.cycling,
                        known: mic.pictureKnown
                    ) { choice in
                        mic.selectPreset(choice)
                    }
                    .padding(.bottom, 16)
                }

                HStack(spacing: 12) {
                    dropButton
                    Button(action: { mic.toggle() }) {
                        Text(mic.running ? "Stop" : "Start")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(mic.running ? Color.white.opacity(0.14) : Color.white)
                            .foregroundStyle(mic.running ? Color.white : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Color.black)
            }
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

    private var sensitivitySlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SENSITIVITY")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(gainText(mic.sensitivity))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(
                value: $mic.sensitivity,
                in: MicTuning.sensitivityMin...MicTuning.sensitivityMax,
                step: 0.05
            )
            .tint(.white)
        }
    }

    private var latencySlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LATENCY")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(latencyText(mic.latencyMs))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(
                value: Binding(
                    get: { Double(mic.latencyMs) },
                    set: { mic.latencyMs = Int($0.rounded()) }
                ),
                in: Double(MicTuning.latencyMin)...Double(MicTuning.latencyMax),
                step: Double(MicTuning.latencyStep)
            )
            .tint(.white)
        }
    }

    private var autoCycleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $mic.autoCycle) {
                Text("AUTO-ADVANCE PRESETS")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .tint(.white)

            if mic.autoCycle {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("INTERVAL")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text("\(mic.cycleSeconds)s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(mic.cycleSeconds) },
                            set: { mic.cycleSeconds = Int($0.rounded()) }
                        ),
                        in: Double(MicTuning.cycleSecondsMin)...Double(MicTuning.cycleSecondsMax),
                        step: 5
                    )
                    .tint(.white)
                }
            }
        }
    }

    private var calibrateControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mic.calibrating {
                Text("KEEP THE ROOM QUIET")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.5))
                ProgressView(value: mic.calibrateProgress)
                    .tint(.white)
                Text(mic.calibrateMessage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                Button(action: { mic.calibrate() }) {
                    Text("Calibrate")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.14))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                if !mic.calibrateMessage.isEmpty {
                    Text(mic.calibrateMessage)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var dropButton: some View {
        Text(mic.dropActive ? "Dropping" : "Drop")
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(mic.dropActive ? Color.white : Color.white.opacity(0.14))
            .foregroundStyle(mic.dropActive ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !dropPressing {
                            dropPressing = true
                            mic.setDrop(pressed: true)
                        }
                    }
                    .onEnded { _ in
                        dropPressing = false
                        mic.setDrop(pressed: false)
                    }
            )
    }

    private func gainText(_ value: Float) -> String {
        if abs(value - value.rounded()) < 0.02 {
            return String(format: "%.0f×", value)
        }
        return String(format: "%.2f×", value)
    }

    private func latencyText(_ ms: Int) -> String {
        if ms > 0 { return "+\(ms) ms" }
        return "\(ms) ms"
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
