import AVKit
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
                ProjectMCanvasView(
                    renderState: visuals.projectMState,
                    audioHub: visuals.audioHub,
                    micReceiver: visuals.micReceiver,
                    micSource: visuals.micSource,
                    paused: scenePhase != .active,
                    onAudioFrame: { drive, metrics in
                        visuals.noteAudioFrame(drive: drive, metrics: metrics)
                    },
                    failure: $failure
                )
                .ignoresSafeArea()
            }

            if visuals.showAudioDebug {
                BeatTestOverlay(
                    drive: visuals.audioDebugDrive,
                    metrics: visuals.audioDebugMetrics
                )
                .zIndex(399)
                MicAudioDebugOverlay(
                    drive: visuals.audioDebugDrive,
                    metrics: visuals.audioDebugMetrics,
                    latencyMs: visuals.latencyMs
                )
                .zIndex(400)
                .allowsHitTesting(false)
            }

            NowPlayingOverlay(
                presetName: visuals.currentPresetName,
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

            if visuals.micLive {
                micMark
            }

            if visuals.showHint {
                hint
            }

            RemoteReader(
                onLeft: { visuals.previous() },
                onRight: { visuals.next() },
                onSelect: { visuals.advance() },
                onLongPress: { visuals.togglePin() },
                onPlayPause: { music.togglePlayback() },
                capturesFocus: !visuals.showMicSettings
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            if visuals.showMicSettings {
                MicSettingsPanel(
                    source: visuals.micSource,
                    sensitivity: visuals.sensitivity,
                    latencyMs: visuals.latencyMs,
                    continuityStatus: visuals.continuityStatus,
                    showAudioDebug: visuals.showAudioDebug,
                    onAudioDebug: { visuals.setShowAudioDebug($0) },
                    onSource: { visuals.setMicSource($0) },
                    onSensitivity: { visuals.setSensitivity($0) },
                    onLatency: { visuals.setLatency($0) },
                    onPair: { visuals.beginContinuityPairing() },
                    onClose: { visuals.closeSettings() }
                )
            }
        }
        .preferredColorScheme(.dark)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                visuals.previous()
            case .right:
                visuals.next()
            case .down:
                if !visuals.showMicSettings {
                    visuals.openSettings()
                }
            default:
                break
            }
        }
        .modifier(CloseMicSettingsOnMenu(open: visuals.showMicSettings) {
            visuals.closeSettings()
        })
        .continuityDevicePicker(isPresented: $visuals.showContinuityPicker) { _ in }
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
        .onChange(of: music.trackID) { _, _ in
            visuals.revealOverlay()
        }
        .task {
            await music.start()
        }
    }

    private var micMark: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(red: 0.45, green: 0.95, blue: 0.62))
                        .frame(width: 12, height: 12)
                    Text(visuals.micName.isEmpty ? "Mic" : visuals.micName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.trailing, 48)
                .padding(.top, 36)
            }
            Spacer()
        }
        .allowsHitTesting(false)
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
            Text("Swipe for another picture. Swipe down for the microphone. Click steps forward. Play and pause starts your music. Hold to keep the title on screen.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(3)
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
        visuals.projectMState.setPaused(!active)
    }
}

/// Menu closes the mic panel. When the panel is closed this modifier is absent,
/// so Menu still leaves the app.
private struct CloseMicSettingsOnMenu: ViewModifier {
    var open: Bool
    var close: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if open {
            content.onExitCommand(perform: close)
        } else {
            content
        }
    }
}
