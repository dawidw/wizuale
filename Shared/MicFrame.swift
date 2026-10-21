import Foundation

/// One analysis packet from Wizuale Mic to the Apple TV.
/// Band values are after the phone's auto gain. They may pass 1 when a kick
/// is louder than the recent peak, up to `MicWire.gainCeiling`, so the hit is
/// not flattened. `onset` decays on the phone over about 70 ms so a dropped
/// datagram still carries the kick.
struct MicFeatures: Equatable, Sendable {
    var bass: Float
    var lowMid: Float
    var mid: Float
    var high: Float
    var loudness: Float
    var onset: Float
    var flux: Float

    static let zero = MicFeatures(
        bass: 0, lowMid: 0, mid: 0, high: 0, loudness: 0, onset: 0, flux: 0
    )
}

/// What crossed the link. Audio rides with the hit slider. A command locks a
/// preset (`-1` restores auto). The TV answers with an ack naming the picture
/// that is actually showing.
enum MicPacket: Equatable, Sendable {
    case audio(sequence: UInt16, features: MicFeatures, sensitivity: Float)
    case command(sequence: UInt16, preset: Int16)
    case ack(preset: Int16, cycling: Bool)
}

/// Little-endian datagram both apps share. Magic bytes on the wire are `MIC1`.
///
/// Audio, 40 bytes: magic u32, kind u16 = 1, sequence u16, seven f32 gains, sensitivity f32.
/// Command, 10 bytes: magic, kind = 2, sequence u16, preset i16.
/// Ack, 10 bytes: magic, kind = 3, preset i16, cycling u16 (1 or 0).
///
/// A 36-byte packet from the first mic build is ignored. Both apps ship together.
enum MicWire {
    static let magic: UInt32 = 0x3143494D
    static let serviceType = "_wizuale._udp"
    static let kindAudio: UInt16 = 1
    static let kindCommand: UInt16 = 2
    static let kindAck: UInt16 = 3
    static let gainCeiling: Float = 2.5
    static let audioBytes = 40
    static let commandBytes = 10
    static let ackBytes = 10

    static func encodeAudio(sequence: UInt16, features: MicFeatures, sensitivity: Float) -> Data {
        var data = Data(capacity: audioBytes)
        write(magic, &data)
        write(kindAudio, &data)
        write(sequence, &data)
        write(gain(features.bass), &data)
        write(gain(features.lowMid), &data)
        write(gain(features.mid), &data)
        write(gain(features.high), &data)
        write(gain(features.loudness), &data)
        write(gain(features.onset), &data)
        write(gain(features.flux), &data)
        write(slider(sensitivity), &data)
        return data
    }

    static func encodeCommand(sequence: UInt16, preset: Int16) -> Data {
        var data = Data(capacity: commandBytes)
        write(magic, &data)
        write(kindCommand, &data)
        write(sequence, &data)
        write(preset, &data)
        return data
    }

    static func encodeAck(preset: Int16, cycling: Bool) -> Data {
        var data = Data(capacity: ackBytes)
        write(magic, &data)
        write(kindAck, &data)
        write(preset, &data)
        write(cycling ? UInt16(1) : UInt16(0), &data)
        return data
    }

    static func decode(_ data: Data) -> MicPacket? {
        guard data.count >= ackBytes else { return nil }
        guard readUInt32(data, 0) == magic else { return nil }
        let kind = readUInt16(data, 4)
        if kind == kindAudio {
            guard data.count >= audioBytes else { return nil }
            let sequence = readUInt16(data, 6)
            guard
                let bass = readGain(data, 8),
                let lowMid = readGain(data, 12),
                let mid = readGain(data, 16),
                let high = readGain(data, 20),
                let loudness = readGain(data, 24),
                let onset = readGain(data, 28),
                let flux = readGain(data, 32),
                let sensitivity = readSlider(data, 36)
            else { return nil }
            return .audio(
                sequence: sequence,
                features: MicFeatures(
                    bass: bass,
                    lowMid: lowMid,
                    mid: mid,
                    high: high,
                    loudness: loudness,
                    onset: onset,
                    flux: flux
                ),
                sensitivity: sensitivity
            )
        }
        if kind == kindCommand {
            guard data.count >= commandBytes else { return nil }
            return .command(sequence: readUInt16(data, 6), preset: readInt16(data, 8))
        }
        if kind == kindAck {
            guard data.count >= ackBytes else { return nil }
            let cycling = readUInt16(data, 8) != 0
            return .ack(preset: readInt16(data, 6), cycling: cycling)
        }
        return nil
    }

    private static func gain(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), gainCeiling)
    }

    private static func slider(_ value: Float) -> Float {
        guard value.isFinite else { return 1 }
        return min(max(value, 0.5), 2)
    }

    private static func write(_ value: UInt32, _ data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private static func write(_ value: UInt16, _ data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func write(_ value: Int16, _ data: inout Data) {
        write(UInt16(bitPattern: value), &data)
    }

    private static func write(_ value: Float, _ data: inout Data) {
        write(value.bitPattern, &data)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readInt16(_ data: Data, _ offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(data, offset))
    }

    private static func readGain(_ data: Data, _ offset: Int) -> Float? {
        let value = Float(bitPattern: readUInt32(data, offset))
        guard value.isFinite else { return nil }
        return min(max(value, 0), gainCeiling)
    }

    private static func readSlider(_ data: Data, _ offset: Int) -> Float? {
        let value = Float(bitPattern: readUInt32(data, offset))
        guard value.isFinite else { return nil }
        return min(max(value, 0.5), 2)
    }
}
