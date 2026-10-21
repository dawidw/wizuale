import Combine
import MusicKit
import UIKit

/// Reads the system Music queue. The app never opens the audio stream:
/// Apple Music is DRM, and the picture only needs the title and the cover.
@MainActor
final class MusicSession: ObservableObject {
    enum Access: Equatable {
        case unknown
        case authorized
        case denied
        case restricted
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: UIImage?
    @Published private(set) var albumColors: AlbumColors?
    @Published private(set) var statusMessage: String?
    @Published private(set) var trackID = ""

    private var pollTask: Task<Void, Never>?
    private var artworkGeneration = 0
    private var lastTrackKey = ""
    private var lastToggle = Date.distantPast

    func start() async {
        switch await MusicAuthorization.request() {
        case .authorized:
            access = .authorized
            statusMessage = nil
        case .denied:
            access = .denied
            statusMessage = "Apple Music access is off. The picture uses its own colors."
        case .restricted:
            access = .restricted
            statusMessage = "Apple Music is restricted on this Apple TV. The picture uses its own colors."
        case .notDetermined:
            access = .unknown
        @unknown default:
            access = .unknown
        }

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    /// Play/pause on the Siri Remote. A stopped queue is filled from
    /// recently played songs, then from the library. An active queue is left alone.
    func togglePlayback() {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.18 else { return }
        lastToggle = now
        guard access == .authorized else { return }

        let player = SystemMusicPlayer.shared
        switch player.state.playbackStatus {
        case .playing:
            player.pause()
            isPlaying = false
        case .paused, .interrupted, .seekingForward, .seekingBackward:
            isPlaying = true
            Task {
                do { try await player.play() }
                catch { isPlaying = player.state.playbackStatus == .playing }
            }
        case .stopped:
            Task { await startFromLibrary() }
        @unknown default:
            Task { try? await player.play() }
        }
    }

    private func refresh() async {
        guard access == .authorized else { return }
        let player = SystemMusicPlayer.shared
        isPlaying = player.state.playbackStatus == .playing

        guard let entry = player.queue.currentEntry else { return }
        let itemTitle = entry.title
        let itemArtist = entry.subtitle ?? ""
        let artURL = entry.artwork?.url(width: 400, height: 400)
        let key = "\(itemTitle)|\(itemArtist)|\(artURL?.absoluteString ?? "")"
        title = itemTitle
        artist = itemArtist
        guard key != lastTrackKey else { return }
        lastTrackKey = key
        trackID = key
        if let artURL {
            await loadArtwork(from: artURL, key: key)
        } else {
            artwork = nil
            albumColors = nil
        }
    }

    private func loadArtwork(from url: URL, key: String) async {
        artworkGeneration += 1
        let generation = artworkGeneration
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard generation == artworkGeneration, key == lastTrackKey else { return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            guard let image = UIImage(data: data) else { return }
            artwork = image
            albumColors = ArtworkPalette.extract(from: image)
        } catch {
            // Keep the previous cover on screen until a newer download wins.
        }
    }

    private func startFromLibrary() async {
        if await play(songs: recentlyPlayed()) { return }
        if await play(songs: librarySongs()) { return }
        statusMessage = "No songs to start. Open Music, play something, then come back."
    }

    private func recentlyPlayed() async -> [Song] {
        do {
            var request = MusicRecentlyPlayedRequest<Song>()
            request.limit = 25
            let response = try await request.response()
            return Array(response.items)
        } catch {
            return []
        }
    }

    private func librarySongs() async -> [Song] {
        do {
            var request = MusicLibraryRequest<Song>()
            request.limit = 25
            let response = try await request.response()
            return Array(response.items)
        } catch {
            return []
        }
    }

    private func play(songs: [Song]) async -> Bool {
        guard !songs.isEmpty else { return false }
        let player = SystemMusicPlayer.shared
        player.queue = MusicPlayer.Queue(for: songs)
        do {
            try await player.play()
            isPlaying = true
            statusMessage = nil
            return true
        } catch {
            return false
        }
    }
}
