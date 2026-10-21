import Foundation
import QuartzCore

/// What one frame needs from the clock. `hasRealTempo` is false when the picture
/// should keep the old time-based pulse.
struct BeatSample: Sendable {
    var bpm: Float
    var kick: Float
    var downbeat: Float
    var beatPhase: Float
    var barPhase: Float
    var phrasePhase: Float
    var beatsPerBar: Float
    var hasRealTempo: Bool
}

/// Phase-aligned to the track position. The renderer reads it every frame;
/// MusicKit is only sampled a few times a second, and this fills the gap.
final class BeatClock: @unchecked Sendable {
    private let lock = NSLock()
    private var realBPM: Double = 0
    private var beatsPerBar = 4
    private var hasReal = false
    private var playing = false
    private var anchorTrackTime: TimeInterval = 0
    private var anchorWall: CFTimeInterval = 0
    private var haveAnchor = false

    func setRealTempo(_ tempo: TrackTempo?) {
        lock.lock()
        defer { lock.unlock() }
        if let tempo, tempo.bpm >= 40 {
            realBPM = tempo.bpm
            beatsPerBar = max(tempo.beatsPerBar, 1)
            hasReal = true
        } else {
            realBPM = 0
            beatsPerBar = 4
            hasReal = false
        }
    }

    /// `time` is `SystemMusicPlayer.playbackTime`. Nil means the player returned
    /// a non-finite time, which MusicKit does when the underlying time is invalid.
    func notePlayback(time: TimeInterval?, playing: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let wall = CACurrentMediaTime()
        let finite = time.flatMap { value -> TimeInterval? in
            guard value.isFinite, value >= 0 else { return nil }
            return value
        }

        if !playing {
            if let finite {
                anchorTrackTime = finite
                haveAnchor = true
            } else if self.playing, haveAnchor {
                anchorTrackTime = extrapolated(at: wall)
            }
            anchorWall = wall
            self.playing = false
            return
        }

        if let finite {
            if !self.playing || !haveAnchor {
                anchorTrackTime = finite
                anchorWall = wall
                haveAnchor = true
            } else {
                let predicted = extrapolated(at: wall)
                if abs(finite - predicted) > 0.4 {
                    anchorTrackTime = finite
                    anchorWall = wall
                } else {
                    // Pull a quarter of the way toward the sample so drift dies
                    // without a one-frame phase jump on every poll.
                    anchorTrackTime = predicted + (finite - predicted) * 0.25
                    anchorWall = wall
                }
            }
        } else if !haveAnchor {
            anchorTrackTime = 0
            anchorWall = wall
            haveAnchor = true
        } else if !self.playing {
            anchorWall = wall
        }
        self.playing = true
    }

    /// Nil when the picture should use the 45 second timer: no matched tempo, or the song is paused.
    func secondsUntilPhraseBoundary() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        guard hasReal, playing, realBPM >= 40 else { return nil }
        let trackTime = extrapolated(at: CACurrentMediaTime())
        return TempoText.secondsUntilPhrase(trackTime: trackTime, bpm: realBPM, beatsPerBar: beatsPerBar)
    }

    func sample(fallbackBPM: Float) -> BeatSample {
        lock.lock()
        defer { lock.unlock() }
        let fallback = max(fallbackBPM, 1)
        guard hasReal, realBPM >= 40 else {
            return BeatSample(
                bpm: fallback,
                kick: 0,
                downbeat: 0,
                beatPhase: 0,
                barPhase: 0,
                phrasePhase: 0,
                beatsPerBar: 4,
                hasRealTempo: false
            )
        }
        let trackTime = haveAnchor ? extrapolated(at: CACurrentMediaTime()) : 0
        let frame = TempoText.musicalFrame(trackTime: trackTime, bpm: realBPM, beatsPerBar: beatsPerBar)
        return BeatSample(
            bpm: Float(realBPM),
            kick: Float(frame.kick),
            downbeat: Float(frame.downbeat),
            beatPhase: Float(frame.beatPhase),
            barPhase: Float(frame.barPhase),
            phrasePhase: Float(frame.phrasePhase),
            beatsPerBar: Float(beatsPerBar),
            hasRealTempo: true
        )
    }

    private func extrapolated(at wall: CFTimeInterval) -> TimeInterval {
        guard haveAnchor else { return 0 }
        if playing {
            return max(0, anchorTrackTime + (wall - anchorWall))
        }
        return max(0, anchorTrackTime)
    }
}
