import Combine
import MusicKit
import UIKit

/// Reads the system Music queue. The app never opens the audio stream:
/// Apple Music is DRM. The picture uses the title, the cover, and — when
/// GetSongBPM has the song — the tempo. Playback position comes from
/// `SystemMusicPlayer.playbackTime`, not from the audio.
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
    /// "116 BPM · 4/4 · Fm" when GetSongBPM matched this song. Empty otherwise.
    @Published private(set) var tempoDetail = ""
    /// True only while a GetSongBPM match is driving the picture.
    @Published private(set) var showsTempoCredit = false

    let beatClock: BeatClock

    private var pollTask: Task<Void, Never>?
    private var artworkGeneration = 0
    private var lastTrackKey = ""
    private var requestedIdentity = ""
    private var appliedIdentity = ""
    private var lookupInFlightIdentity = ""
    private var lookupGeneration = 0
    private var retryIdentity = ""
    private var retryAfter = Date.distantPast
    private var lastToggle = Date.distantPast

    init(beatClock: BeatClock) {
        self.beatClock = beatClock
    }

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
                // Often enough that a seek corrects the beat clock within a quarter second.
                try? await Task.sleep(nanoseconds: 250_000_000)
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
        let playing = player.state.playbackStatus == .playing
        isPlaying = playing
        // NaN means MusicKit has no finite time yet. The clock keeps extrapolating.
        let rawTime = player.playbackTime
        let playTime: TimeInterval? = (rawTime.isFinite && rawTime >= 0) ? rawTime : nil
        beatClock.notePlayback(time: playTime, playing: playing)

        guard let entry = player.queue.currentEntry else { return }
        let itemTitle = entry.title
        let itemArtist = entry.subtitle ?? ""
        let artURL = entry.artwork?.url(width: 400, height: 400)
        let key = "\(itemTitle)|\(itemArtist)|\(artURL?.absoluteString ?? "")"
        title = itemTitle
        artist = itemArtist

        considerLookup(title: itemTitle, artist: itemArtist)

        guard key != lastTrackKey else { return }
        lastTrackKey = key
        trackID = key
        if let artURL {
            let artworkKey = key
            Task { await self.loadArtwork(from: artURL, key: artworkKey) }
        } else {
            artwork = nil
            albumColors = nil
        }
    }

    /// One lookup per song. A network failure retries after a short pause;
    /// a definitive miss does not. A newer song cancels an older result.
    private func considerLookup(title: String, artist: String) {
        let identity = "\(title)\n\(artist)"
        let sameRequest = identity == requestedIdentity
        if sameRequest, identity == appliedIdentity { return }
        if sameRequest, identity == lookupInFlightIdentity { return }
        if sameRequest, identity == retryIdentity, Date() < retryAfter { return }

        requestedIdentity = identity
        lookupInFlightIdentity = identity
        lookupGeneration += 1
        let generation = lookupGeneration
        beatClock.setRealTempo(nil)
        tempoDetail = ""
        showsTempoCredit = false
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appliedIdentity = identity
            lookupInFlightIdentity = ""
            return
        }
        Task { @MainActor [weak self] in
            let outcome = await TempoService.shared.lookup(title: title, artist: artist)
            self?.applyTempo(outcome, generation: generation, identity: identity)
        }
    }

    private func applyTempo(_ outcome: TempoOutcome, generation: Int, identity: String) {
        guard generation == lookupGeneration else { return }
        lookupInFlightIdentity = ""
        switch outcome {
        case .matched(let tempo):
            appliedIdentity = identity
            beatClock.setRealTempo(tempo)
            tempoDetail = tempo.detail
            showsTempoCredit = true
        case .noMatch:
            appliedIdentity = identity
        case .unavailable:
            retryIdentity = identity
            retryAfter = Date().addingTimeInterval(8)
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
