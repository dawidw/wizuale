import SwiftUI
import UIKit

/// Horizontal preset picker. `choice` is `-1` for auto, otherwise an index into `MilkPresetCatalog.presets`.
struct PresetStrip: View {
    var active: Int
    var cycling: Bool
    var known: Bool
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESETS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 22)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PresetCard(title: "Auto", selected: known && cycling) {
                            onSelect(Int(PresetWire.auto))
                        }
                        .id(Int(PresetWire.auto))
                        ForEach(MilkPresetCatalog.groupedPresets, id: \.group) { section in
                            PresetGroupLabel(title: section.group)
                            ForEach(section.presets) { preset in
                                PresetCard(
                                    title: preset.displayName,
                                    thumbnail: PresetThumbnails.image(for: preset),
                                    selected: known && preset.id == active && !cycling,
                                    playing: known && preset.id == active
                                ) {
                                    onSelect(preset.id)
                                }
                                .id(preset.id)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
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

private struct PresetGroupLabel: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.42))
            .frame(height: 58, alignment: .bottomLeading)
            .padding(.leading, 2)
    }
}

private struct PresetCard: View {
    var title: String
    var thumbnail: UIImage? = nil
    var selected: Bool
    var playing: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 58)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 92, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(ring, lineWidth: selected ? 2.5 : 1.5)
                    }
                Text(title)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(selected || playing ? 0.95 : 0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 92, height: 28, alignment: .topLeading)
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

/// Bundled preset thumbnails (`Presets/thumbs/*.jpg`), decoded once and kept in memory.
@MainActor
enum PresetThumbnails {
    private static var cache: [Int: UIImage] = [:]
    private static var missing: Set<Int> = []

    static func image(for preset: MilkPreset) -> UIImage? {
        if let hit = cache[preset.id] { return hit }
        if missing.contains(preset.id) { return nil }
        guard let url = MilkPresetCatalog.thumbnailURL(for: preset),
              let image = UIImage(contentsOfFile: url.path) else {
            missing.insert(preset.id)
            return nil
        }
        cache[preset.id] = image
        return image
    }
}
