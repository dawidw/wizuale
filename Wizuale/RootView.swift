import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var visuals: VisualSession
    @StateObject private var music: MusicSession
    @State private var failure: String?

    init() {
        let clock = BeatClock()
        _visuals = StateObject(wrappedValue: VisualSession(beatClock: clock))
        _music = StateObject(wrappedValue: MusicSession(beatClock: clock))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let failure {
                Text(failure)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(80)
            } else {
                MetalCanvasView(
                    state: visuals.renderState,
                    beatClock: visuals.beatClock,
                    paused: scenePhase != .active,
                    failure: $failure
                )
                .ignoresSafeArea()
            }

            NowPlayingOverlay(
                presetName: visuals.currentPreset.name,
                title: music.title,
                artist: music.artist,
                artwork: music.artwork,
                statusMessage: music.statusMessage,
                pinned: visuals.overlayPinned,
                isPlaying: music.isPlaying,
                visible: visuals.overlayVisible,
                tempoDetail: music.tempoDetail,
                showsTempoCredit: music.showsTempoCredit
            )

            if music.showsTempoCredit && !visuals.overlayVisible {
                tempoCredit
            }

            if visuals.showHint {
                hint
            }

            RemoteReader(
                onLeft: { visuals.previous() },
                onRight: { visuals.next() },
                onSelect: { visuals.advance() },
                onLongPress: { visuals.togglePin() },
                onPlayPause: { music.togglePlayback() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                visuals.previous()
            case .right:
                visuals.next()
            default:
                break
            }
        }
        .onPlayPauseCommand {
            music.togglePlayback()
        }
        .onAppear {
            applyIdleTimer(scenePhase)
            visuals.start()
        }
        .onChange(of: scenePhase) { _, phase in
            applyIdleTimer(phase)
        }
        .onChange(of: music.albumColors) { _, colors in
            visuals.renderState.setAlbum(colors)
        }
        .onChange(of: music.trackID) { _, _ in
            visuals.revealOverlay()
        }
        .task {
            await music.start()
        }
    }

    /// Stays up after the title card fades. GetSongBPM requires a visible credit while their data is used.
    private var tempoCredit: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("Tempo data by GetSongBPM")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.trailing, 56)
                    .padding(.bottom, 36)
            }
        }
        .allowsHitTesting(false)
    }

    private var hint: some View {
        VStack {
            Text("Swipe for another picture. Click steps forward. Play and pause starts your music. Hold to keep the title on screen.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .padding(.top, 36)
                .padding(.horizontal, 90)
            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func applyIdleTimer(_ phase: ScenePhase) {
        let active = phase == .active
        UIApplication.shared.isIdleTimerDisabled = active
        visuals.renderState.setPaused(!active)
    }
}
