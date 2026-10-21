import SwiftUI
import UIKit

/// Corner card. It fades out on its own; holding Select keeps it up.
struct NowPlayingOverlay: View {
    var presetName: String
    var title: String
    var artist: String
    var artwork: UIImage?
    var statusMessage: String?
    var pinned: Bool
    var isPlaying: Bool
    var visible: Bool

    private var headline: String {
        title.isEmpty ? "Nothing playing" : title
    }

    private var detail: String {
        if title.isEmpty {
            if let statusMessage, !statusMessage.isEmpty { return statusMessage }
            return "Press play to start your recent songs."
        }
        if !isPlaying {
            return artist.isEmpty ? "Paused" : "\(artist)  ·  Paused"
        }
        if !artist.isEmpty { return artist }
        return statusMessage ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                card
                Spacer(minLength: 0)
            }
            .padding(.leading, 56)
            .padding(.bottom, 42)
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 22)
        .animation(.easeInOut(duration: 0.55), value: visible)
        .allowsHitTesting(false)
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 22) {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(presetName.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.62))
                    if pinned {
                        Text("Title pinned")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                Text(headline)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(.trailing, 8)
        }
        .padding(.leading, artwork == nil ? 28 : 16)
        .padding(.trailing, 32)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.38), radius: 24, y: 14)
    }
}
