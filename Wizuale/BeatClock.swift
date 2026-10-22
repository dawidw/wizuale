import Darwin
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

/// Phase-aligned to the track position. When a microphone is live, a PLL
/// nudges that phase toward the kicks it hears. GetSongBPM is the guess
/// the lock starts from, and the clock it falls back to when the kicks stop.
/// The renderer reads it every frame; MusicKit is only sampled a few times
/// a second, and this fills the gap.
final class BeatClock: @unchecked Sendable {
    private let lock = NSLock()
    private var realBPM: Double = 0
    private var beatsPerBar = 4
    private var hasReal = false
    private var playing = false
    private var anchorTrackTime: TimeInterval = 0
    private var anchorWall: CFTimeInterval = 0
    private var haveAnchor = false
    private var visualLatency: TimeInterval = 0

    private var lockedBPM: Double = 0
    private var beatCursor: Double = 0
    private var lockWeight: Double = 0
    private var lastKickWall: CFTimeInterval = 0
    private var kickArmed = true

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

    /// Positive latency delays the song clock. Negative latency leads it.
    /// The mic delay line is separate; this only moves the musical frame.
    func setVisualLatency(ms: Int) {
        lock.lock()
        visualLatency = Double(ms) / 1000
        lock.unlock()
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

    /// Feed the onset the picture is already using (after the latency buffer).
    /// Call once per frame, and do not call `sample` from here.
    func noteMic(onset: Float, presence: Float, dt: Float, fallbackBPM: Float) {
        lock.lock()
        defer { lock.unlock() }
        let dtSafe = Double(min(max(dt, 0), 0.1))
        let live = presence > 0.35
        let now = CACurrentMediaTime()
        if !live {
            lockWeight *= Darwin.exp(-dtSafe / 1.4)
            if hasReal, realBPM >= 40 {
                if lockedBPM < 40 { lockedBPM = realBPM }
                let glide = 1 - Darwin.exp(-dtSafe / 1.2)
                lockedBPM += (realBPM - lockedBPM) * glide
            }
            if onset < 0.28 { kickArmed = true }
            return
        }

        if lockedBPM < 40 {
            let seed = (hasReal && realBPM >= 40) ? realBPM : Double(fallbackBPM)
            lockedBPM = min(max(seed, 40), 220)
        }
        beatCursor += lockedBPM / 60.0 * dtSafe
        if lastKickWall > 0, now - lastKickWall > 2 {
            lockWeight *= Darwin.exp(-dtSafe / 1.4)
        }

        if kickArmed && onset > 0.55 {
            kickArmed = false
            let interval = lastKickWall > 0 ? now - lastKickWall : 0
            if interval >= 0.22 && interval <= 1.6 {
                var measured = 60.0 / interval
                let guess = lockedBPM
                while measured > guess * 1.45 && measured * 0.5 >= 40 {
                    measured *= 0.5
                }
                while measured < guess / 1.45 && measured * 2 <= 220 {
                    measured *= 2
                }
                let tempoGain = lockWeight < 0.2 ? 0.35 : 0.1
                lockedBPM = min(max(lockedBPM + (measured - lockedBPM) * tempoGain, 40), 220)
                var phase = beatCursor - floor(beatCursor)
                if phase > 0.5 { phase -= 1 }
                let gain = lockWeight < 0.25 ? 1.0 : 0.62
                let nudge = min(max(-phase * gain, -0.45), 0.45)
                beatCursor += nudge
                lockWeight = min(1, lockWeight + 0.15)
            } else {
                var phase = beatCursor - floor(beatCursor)
                if phase > 0.5 { phase -= 1 }
                beatCursor += min(max(-phase, -0.45), 0.45)
                lockWeight = max(lockWeight, 0.2)
            }
            lastKickWall = now
        } else if onset < 0.28 {
            kickArmed = true
        }
    }

    /// Nil when the picture should use the 45 second timer: no matched tempo,
    /// the song is paused, and the mic lock is not holding a phrase.
    func secondsUntilPhraseBoundary() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        if lockWeight > 0.45 && lockedBPM >= 40 {
            let bars = max(beatsPerBar, 1)
            let phraseBeats = Double(bars * TempoText.barsPerPhrase)
            let wrapped = beatCursor - floor(beatCursor / phraseBeats) * phraseBeats
            let secondsPerPhrase = phraseBeats * 60 / lockedBPM
            let since = wrapped * 60 / lockedBPM
            if since <= 0.12 { return 0 }
            return secondsPerPhrase - since
        }
        guard hasReal, playing, realBPM >= 40 else { return nil }
        let trackTime = visualTrackTime(at: CACurrentMediaTime())
        return TempoText.secondsUntilPhrase(trackTime: trackTime, bpm: realBPM, beatsPerBar: beatsPerBar)
    }

    func sample(fallbackBPM: Float) -> BeatSample {
        lock.lock()
        defer { lock.unlock() }
        let fallback = max(fallbackBPM, 1)
        let pllReady = lockWeight > 0.3 && lockedBPM >= 40
        if pllReady {
            let pll = frame(beats: beatCursor, bpm: lockedBPM, bars: beatsPerBar, real: true)
            let full = lockWeight > 0.85 || !hasReal || realBPM < 40
            if full { return pll }
            let song = songFrame(fallback: fallback)
            let mix = Float(min(max((lockWeight - 0.3) / 0.55, 0), 1))
            return blend(song, pll, mix)
        }
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
        return songFrame(fallback: fallback)
    }

    private func songFrame(fallback: Float) -> BeatSample {
        guard hasReal, realBPM >= 40 else {
            return BeatSample(
                bpm: fallback, kick: 0, downbeat: 0, beatPhase: 0, barPhase: 0,
                phrasePhase: 0, beatsPerBar: 4, hasRealTempo: false
            )
        }
        let trackTime = visualTrackTime(at: CACurrentMediaTime())
        let musical = TempoText.musicalFrame(trackTime: trackTime, bpm: realBPM, beatsPerBar: beatsPerBar)
        return BeatSample(
            bpm: Float(realBPM),
            kick: Float(musical.kick),
            downbeat: Float(musical.downbeat),
            beatPhase: Float(musical.beatPhase),
            barPhase: Float(musical.barPhase),
            phrasePhase: Float(musical.phrasePhase),
            beatsPerBar: Float(beatsPerBar),
            hasRealTempo: true
        )
    }

    private func frame(beats: Double, bpm: Double, bars: Int, real: Bool) -> BeatSample {
        let barBeats = Double(max(bars, 1))
        let safeBPM = max(bpm, 1)
        let beatPhase = beats - floor(beats)
        let bar = beats / barBeats
        let barPhase = bar - floor(bar)
        let phraseBeats = barBeats * Double(TempoText.barsPerPhrase)
        let phrase = beats / phraseBeats
        let phrasePhase = phrase - floor(phrase)
        let whole = Int(floor(beats))
        let isDownbeat = whole % max(bars, 1) == 0
        let kick = TempoText.envelope(phase: beatPhase, width: 0.30)
        let downbeat = isDownbeat ? TempoText.envelope(phase: beatPhase, width: 0.42) : 0
        return BeatSample(
            bpm: Float(safeBPM),
            kick: Float(kick),
            downbeat: Float(downbeat),
            beatPhase: Float(beatPhase),
            barPhase: Float(barPhase),
            phrasePhase: Float(phrasePhase),
            beatsPerBar: Float(barBeats),
            hasRealTempo: real
        )
    }

    private func blend(_ song: BeatSample, _ pll: BeatSample, _ mix: Float) -> BeatSample {
        BeatSample(
            bpm: song.bpm + (pll.bpm - song.bpm) * mix,
            kick: song.kick + (pll.kick - song.kick) * mix,
            downbeat: song.downbeat + (pll.downbeat - song.downbeat) * mix,
            beatPhase: wrapMix(song.beatPhase, pll.beatPhase, mix),
            barPhase: wrapMix(song.barPhase, pll.barPhase, mix),
            phrasePhase: wrapMix(song.phrasePhase, pll.phrasePhase, mix),
            beatsPerBar: pll.beatsPerBar,
            hasRealTempo: true
        )
    }

    private func wrapMix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var delta = b - a
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        var mixed = a + delta * t
        if mixed < 0 { mixed += 1 }
        if mixed >= 1 { mixed -= 1 }
        return mixed
    }

    /// Assumes the lock is held. Subtracts the visual latency from the playhead.
    private func visualTrackTime(at wall: CFTimeInterval) -> TimeInterval {
        let raw = haveAnchor ? extrapolated(at: wall) : 0
        return max(0, raw - visualLatency)
    }

    private func extrapolated(at wall: CFTimeInterval) -> TimeInterval {
        guard haveAnchor else { return 0 }
        if playing {
            return max(0, anchorTrackTime + (wall - anchorWall))
        }
        return max(0, anchorTrackTime)
    }
}
