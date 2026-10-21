import SwiftUI

/// Horizontal preset picker. `choice` is `-1` for auto, otherwise an index into `MilkPresetCatalog.presets`.
struct PresetStrip: View {
    var active: Int
    var cycling: Bool
    var known: Bool
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 28)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        PresetCard(title: "Auto", selected: known && cycling) {
                            onSelect(Int(PresetWire.auto))
                        }
                        .id(Int(PresetWire.auto))
                        ForEach(MilkPresetCatalog.presets) { preset in
                            PresetCard(
                                title: preset.displayName,
                                selected: known && preset.id == active && !cycling,
                                playing: known && preset.id == active
                            ) {
                                onSelect(preset.id)
                            }
                            .id(preset.id)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo(active, anchor: .center)
                }
                .onChange(of: active) { _, value in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
                .onChange(of: cycling) { _, _ in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(active, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct PresetCard: View {
    var title: String
    var selected: Bool
    var playing: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ring, lineWidth: selected ? 2.5 : 1.5)
                    }
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(selected || playing ? 0.95 : 0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 116, height: 32, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
    }

    private var ring: Color {
        if selected { return .white }
        if playing { return .white.opacity(0.72) }
        return .white.opacity(0.16)
    }
}
