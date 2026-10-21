import Foundation

/// One analysis packet from Wizuale Mic to the Apple TV.
/// Values are 0...1 after the phone's auto gain. `onset` is a kick that
/// decays over about 80 ms so a dropped datagram still carries the hit.
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

/// Little-endian datagram both apps share. 36 bytes:
/// magic u32, version u16, sequence u16, then seven f32s in `MicFeatures` order.
/// Magic bytes on the wire are `MIC1`.
enum MicWire {
    static let magic: UInt32 = 0x3143494D
    static let version: UInt16 = 1
    static let byteCount = 36
    static let serviceType = "_wizuale._udp"

    static func encode(sequence: UInt16, features: MicFeatures) -> Data {
        var data = Data(capacity: byteCount)
        write(magic, &data)
        write(version, &data)
        write(sequence, &data)
        write(unit(features.bass), &data)
        write(unit(features.lowMid), &data)
        write(unit(features.mid), &data)
        write(unit(features.high), &data)
        write(unit(features.loudness), &data)
        write(unit(features.onset), &data)
        write(unit(features.flux), &data)
        return data
    }

    static func decode(_ data: Data) -> (sequence: UInt16, features: MicFeatures)? {
        guard data.count >= byteCount else { return nil }
        guard readUInt32(data, 0) == magic else { return nil }
        guard readUInt16(data, 4) == version else { return nil }
        let sequence = readUInt16(data, 6)
        guard
            let bass = readUnit(data, 8),
            let lowMid = readUnit(data, 12),
            let mid = readUnit(data, 16),
            let high = readUnit(data, 20),
            let loudness = readUnit(data, 24),
            let onset = readUnit(data, 28),
            let flux = readUnit(data, 32)
        else { return nil }
        return (
            sequence,
            MicFeatures(
                bass: bass,
                lowMid: lowMid,
                mid: mid,
                high: high,
                loudness: loudness,
                onset: onset,
                flux: flux
            )
        )
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
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

    private static func readUnit(_ data: Data, _ offset: Int) -> Float? {
        let value = Float(bitPattern: readUInt32(data, offset))
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}
