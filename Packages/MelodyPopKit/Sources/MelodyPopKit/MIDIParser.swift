import Foundation

public enum MIDIMessage: Equatable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case other

    public static let sustainController: UInt8 = 64
}

/// Parses a MIDI 1.0 byte stream (running status, interleaved real-time bytes, SysEx skipping).
/// A Note On with velocity 0 is reported as Note Off, as the MIDI spec requires.
public struct MIDIByteParser: Sendable {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    private var inSysEx = false

    public init() {}

    public mutating func parse<S: Sequence>(_ bytes: S) -> [MIDIMessage] where S.Element == UInt8 {
        var out: [MIDIMessage] = []
        for b in bytes {
            if b >= 0xF8 { continue } // real-time: clock, start, stop, active sensing… never break running status
            if b == 0xF0 { inSysEx = true; continue }
            if b == 0xF7 { inSysEx = false; continue }
            if b & 0x80 != 0 {
                inSysEx = false
                if b >= 0xF0 { status = 0; data.removeAll(); continue } // system common cancels running status
                status = b
                data.removeAll(keepingCapacity: true)
                continue
            }
            if inSysEx || status == 0 { continue }
            data.append(b)
            let needed = MIDIByteParser.dataLength(for: status)
            if data.count == needed {
                out.append(MIDIByteParser.message(status: status, data1: data[0], data2: needed > 1 ? data[1] : 0))
                data.removeAll(keepingCapacity: true)
            }
        }
        return out
    }

    static func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1
        default: return 2
        }
    }

    static func message(status: UInt8, data1: UInt8, data2: UInt8) -> MIDIMessage {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x90:
            return data2 == 0 ? .noteOff(channel: channel, note: data1, velocity: 0) : .noteOn(channel: channel, note: data1, velocity: data2)
        case 0x80:
            return .noteOff(channel: channel, note: data1, velocity: data2)
        case 0xB0:
            return .controlChange(channel: channel, controller: data1, value: data2)
        default:
            return .other
        }
    }
}

/// Parses Universal MIDI Packet words as delivered by `MIDIInputPortCreateWithProtocol`.
/// Handles MIDI 1.0 channel-voice (type 0x2) and MIDI 2.0 channel-voice (type 0x4) messages.
public enum UMPParser {
    public static func wordCount(forMessageType mt: UInt32) -> Int {
        switch mt {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    public static func messages(from words: [UInt32]) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            let mt = w >> 28
            let n = wordCount(forMessageType: mt)
            if mt == 0x2 {
                let status = UInt8((w >> 16) & 0xFF)
                let d1 = UInt8((w >> 8) & 0x7F)
                let d2 = UInt8(w & 0x7F)
                out.append(MIDIByteParser.message(status: status, data1: d1, data2: d2))
            } else if mt == 0x4, i + 1 < words.count {
                let status = UInt8((w >> 16) & 0xFF)
                let channel = status & 0x0F
                let index = UInt8((w >> 8) & 0x7F)
                let w2 = words[i + 1]
                switch status & 0xF0 {
                case 0x90:
                    let v16 = UInt16(w2 >> 16)
                    let v7 = UInt8(v16 >> 9)
                    // MIDI 2.0 note-on with velocity 0 is a real note-on; map to minimum audible velocity.
                    out.append(.noteOn(channel: channel, note: index, velocity: max(1, v7)))
                case 0x80:
                    out.append(.noteOff(channel: channel, note: index, velocity: UInt8((w2 >> 25) & 0x7F)))
                case 0xB0:
                    out.append(.controlChange(channel: channel, controller: index, value: UInt8(w2 >> 25)))
                default:
                    out.append(.other)
                }
            }
            i += n
        }
        return out
    }
}
