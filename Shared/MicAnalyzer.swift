import AVFoundation
import Darwin
import Foundation

/// Biquad in direct form I. Coefficients are the RBJ cookbook, already divided by a0.
struct Biquad {
    var b0: Float = 0
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        if abs(y) < 1e-20 { return 0 }
        return y
    }

    static func lowpass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        coefficients(kind: 0, cutoff: cutoff, sampleRate: sampleRate, q: q)
    }

    static func bandpass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        coefficients(kind: 1, cutoff: cutoff, sampleRate: sampleRate, q: q)
    }

    static func highpass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        coefficients(kind: 2, cutoff: cutoff, sampleRate: sampleRate, q: q)
    }

    /// kind 0 lowpass, 1 constant-peak bandpass, 2 highpass.
    private static func coefficients(kind: Int, cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        let rate = max(sampleRate, 8_000)
        let fc = min(max(cutoff, 20), rate * 0.45)
        let resonance = max(q, 0.2)
        let w0 = 2 * Double.pi * fc / rate
        let cosine = Darwin.cos(w0)
        let sine = Darwin.sin(w0)
        let alpha = sine / (2 * resonance)
        let b0: Double
        let b1: Double
        let b2: Double
        if kind == 1 {
            b0 = alpha
            b1 = 0
            b2 = -alpha
        } else if kind == 2 {
            b0 = (1 + cosine) / 2
            b1 = -(1 + cosine)
            b2 = (1 + cosine) / 2
        } else {
            b0 = (1 - cosine) / 2
            b1 = 1 - cosine
            b2 = (1 - cosine) / 2
        }
        let a0 = 1 + alpha
        var filter = Biquad()
        filter.b0 = Float(b0 / a0)
        filter.b1 = Float(b1 / a0)
        filter.b2 = Float(b2 / a0)
        filter.a1 = Float((-2 * cosine) / a0)
        filter.a2 = Float((1 - alpha) / a0)
        return filter
    }
}

/// Slow attack, slow release. A short kick can rise above the running peak
/// instead of being pinned at 1, so the TV still hears the transient.
struct Normalizer {
    var peak: Float = 1e-4
    var floor: Float = 1e-6

    /// Start the gain from a measured noise level so the first notes are not
    /// either silent or slammed against the ceiling.
    mutating func seed(noise: Float) {
        let base = max(noise, 0)
        floor = 0
        peak = max(base * 8, 1e-5)
    }

    mutating func normalize(_ energy: Float, dt: Float) -> Float {
        let dtSafe = max(dt, 0.0001)
        if energy > peak {
            peak += (energy - peak) * (1 - expf(-dtSafe / 0.45))
        } else {
            peak += (energy - peak) * (1 - expf(-dtSafe / 5.5))
        }
        peak = max(peak, 1e-8)
        if energy < floor {
            floor += (energy - floor) * (1 - expf(-dtSafe / 0.35))
        } else {
            floor += (energy - floor) * (1 - expf(-dtSafe / 8))
        }
        floor = min(floor, peak * 0.5)
        let span = max(peak - floor, peak * 0.22, 1e-8)
        return min(max((energy - floor) / span, 0), 1.8)
    }
}

/// Four bands plus a kick. Mutated only on the audio tap.
struct BandAnalyzer {
    private(set) var lastRaw = MicBandEnergy.zero

    private var filters: [Biquad] = []
    private var builtRate: Double = 0
    private var gains = [Normalizer(), Normalizer(), Normalizer(), Normalizer()]
    private var loudGain = Normalizer()
    private var fluxGain = Normalizer()
    private var previousEnergy = [Float](repeating: 0, count: 4)
    private var previousBassPeak: Float = 0
    private var meanBassFlux: Float = 0
    private var onset: Float = 0
    private var refractory: Float = 0
    private var havePrevious = false
    private var noise = MicNoiseFloor.zero

    mutating func apply(floor: MicNoiseFloor) {
        noise = floor
        if floor.bass > 0 { gains[0].seed(noise: floor.bass) }
        if floor.lowMid > 0 { gains[1].seed(noise: floor.lowMid) }
        if floor.mid > 0 { gains[2].seed(noise: floor.mid) }
        if floor.high > 0 { gains[3].seed(noise: floor.high) }
        if floor.loudness > 0 { loudGain.seed(noise: floor.loudness) }
    }

    mutating func consume(_ samples: [Float], sampleRate: Double) -> MicFeatures {
        let count = samples.count
        guard count > 0 else { return .zero }
        let rate = max(sampleRate, 8_000)
        if filters.count != 4 || abs(rate - builtRate) > 1 {
            filters = [
                Biquad.lowpass(cutoff: 110, sampleRate: rate, q: 0.707),
                Biquad.bandpass(cutoff: 300, sampleRate: rate, q: 0.85),
                Biquad.bandpass(cutoff: 1400, sampleRate: rate, q: 0.8),
                Biquad.highpass(cutoff: 5000, sampleRate: rate, q: 0.707)
            ]
            builtRate = rate
            havePrevious = false
        }

        var energy = [Float](repeating: 0, count: 4)
        var bassPeak: Float = 0
        var loudSum: Float = 0
        for sample in samples {
            loudSum += sample * sample
            for band in 0..<4 {
                let shaped = filters[band].process(sample)
                energy[band] += shaped * shaped
                if band == 0 {
                    bassPeak = max(bassPeak, abs(shaped))
                }
            }
        }
        let inv = 1 / Float(count)
        for band in 0..<4 {
            energy[band] *= inv
        }
        let loudRaw = loudSum * inv
        lastRaw = MicBandEnergy(
            bass: energy[0],
            lowMid: energy[1],
            mid: energy[2],
            high: energy[3],
            loudness: loudRaw
        )
        let dt = Float(Double(count) / rate)

        var fluxRaw: Float = 0
        if havePrevious {
            for band in 0..<4 {
                fluxRaw += max(0, energy[band] - previousEnergy[band])
            }
        } else {
            previousBassPeak = bassPeak
        }
        previousEnergy = energy
        havePrevious = true

        energy[0] = max(0, energy[0] - noise.bass)
        energy[1] = max(0, energy[1] - noise.lowMid)
        energy[2] = max(0, energy[2] - noise.mid)
        energy[3] = max(0, energy[3] - noise.high)
        let loudClean = max(0, loudRaw - noise.loudness)

        var shaped = [Float](repeating: 0, count: 4)
        for band in 0..<4 {
            shaped[band] = gains[band].normalize(energy[band], dt: dt)
        }
        let loudness = loudGain.normalize(loudClean, dt: dt)
        let flux = fluxGain.normalize(fluxRaw, dt: dt)

        let bassFlux = max(0, bassPeak - previousBassPeak)
        previousBassPeak = bassPeak
        meanBassFlux += (bassFlux - meanBassFlux) * 0.06
        let gate = max(meanBassFlux * 1.7, 0.00008)
        if bassFlux > gate && shaped[0] > 0.28 && loudness > 0.12 && refractory <= 0 {
            let over = min(bassFlux / gate, 3)
            onset = min(1.7, 0.85 + 0.28 * over)
            refractory = 0.09
        } else {
            onset *= expf(-dt / 0.07)
            refractory = max(0, refractory - dt)
        }

        return MicFeatures(
            bass: shaped[0],
            lowMid: shaped[1],
            mid: shaped[2],
            high: shaped[3],
            loudness: loudness,
            onset: min(max(onset, 0), 1.7),
            flux: flux
        )
    }
}

/// Downmix a tap buffer to mono floats. Shared by the phone and the TV mic.
enum MicPCM {
    static func monoFloats(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        if let channels = buffer.floatChannelData {
            let count = Int(buffer.format.channelCount)
            guard count > 0 else { return [] }
            var mono = [Float](repeating: 0, count: frames)
            let scale = 1 / Float(count)
            for channel in 0..<count {
                let samples = channels[channel]
                for frame in 0..<frames {
                    mono[frame] += samples[frame] * scale
                }
            }
            return mono
        }
        return convertedMono(from: buffer, frames: frames)
    }

    private static func convertedMono(from buffer: AVAudioPCMBuffer, frames: Int) -> [Float] {
        guard
            let desired = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: buffer.format.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: buffer.format, to: desired),
            let converted = AVAudioPCMBuffer(pcmFormat: desired, frameCapacity: AVAudioFrameCount(frames))
        else { return [] }
        var fed = false
        var error: NSError?
        let input: AVAudioConverterInputBlock = { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: converted, error: &error, withInputFrom: input)
        guard error == nil, let channels = converted.floatChannelData else { return [] }
        let got = Int(converted.frameLength)
        guard got > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channels[0], count: got))
    }
}
