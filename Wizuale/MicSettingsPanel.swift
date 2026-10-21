import AVKit
import SwiftUI

/// Secondary mic controls on the TV. The phone app is where latency and
/// sensitivity normally live; this panel is here for Continuity, when the
/// phone app is not the source.
struct MicSettingsPanel: View {
    var source: MicInputSource
    var sensitivity: Float
    var latencyMs: Int
    var continuityStatus: String
    var onSource: (MicInputSource) -> Void
    var onSensitivity: (Float) -> Void
    var onLatency: (Int) -> Void
    var onPair: () -> Void
    var onClose: () -> Void

    @State private var pairNote = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text("Microphone")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)

                ForEach(MicInputSource.allCases) { item in
                    Button {
                        onSource(item)
                    } label: {
                        HStack {
                            Text(item.title)
                            Spacer()
                            if source == item {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.card)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sensitivity")
                            .font(.system(size: 24, weight: .medium))
                        Spacer()
                        Text(sensitivityText(sensitivity))
                            .font(.system(size: 24, weight: .semibold))
                    }
                    HStack(spacing: 16) {
                        Button("−") { onSensitivity(max(MicTuning.sensitivityMin, sensitivity - 0.25)) }
                            .buttonStyle(.card)
                        Button("+") { onSensitivity(min(MicTuning.sensitivityMax, sensitivity + 0.25)) }
                            .buttonStyle(.card)
                    }
                }

                HStack(spacing: 16) {
                    Text("Latency \(latencyLabel(latencyMs))")
                        .font(.system(size: 24, weight: .medium))
                    Spacer()
                    Button("−") { onLatency(max(MicTuning.latencyMin, latencyMs - MicTuning.latencyStep)) }
                        .buttonStyle(.card)
                    Button("+") { onLatency(min(MicTuning.latencyMax, latencyMs + MicTuning.latencyStep)) }
                        .buttonStyle(.card)
                }

                Button("Pair Continuity Microphone") {
                    if AVContinuityDevicePickerViewController.isSupported {
                        onPair()
                    } else {
                        pairNote = "This Apple TV cannot use a Continuity Microphone."
                    }
                }
                .buttonStyle(.card)
                .disabled(source != .continuity)

                if !continuityStatus.isEmpty {
                    Text(continuityStatus)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if !pairNote.isEmpty {
                    Text(pairNote)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                }

                Button("Done", action: onClose)
                    .buttonStyle(.card)
            }
            .padding(48)
            .frame(maxWidth: 980)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .focusSection()
    }

    private func sensitivityText(_ value: Float) -> String {
        if abs(value - value.rounded()) < 0.02 {
            return String(format: "%.0f×", value)
        }
        return String(format: "%.2f×", value)
    }

    private func latencyLabel(_ ms: Int) -> String {
        if ms > 0 { return "+\(ms) ms" }
        return "\(ms) ms"
    }
}
