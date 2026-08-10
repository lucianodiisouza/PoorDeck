import CryptoKit
import Foundation

/// Minimal WebSocket (RFC 6455) helpers: the handshake accept key plus text /
/// close / ping-pong frame coding. We only need text frames in both directions,
/// so this stays small — no fragmentation on the way out, and inbound frames are
/// parsed one complete frame at a time from an accumulating buffer.
enum WebSocket {

    static let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// `Sec-WebSocket-Accept` value for a given client key.
    static func acceptKey(for clientKey: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((clientKey + magicGUID).utf8))
        return Data(digest).base64EncodedString()
    }

    enum Opcode: UInt8 {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    /// Encode a server->client frame (never masked, single unfragmented frame).
    static func encode(_ payload: Data, opcode: Opcode = .text) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode.rawValue) // FIN + opcode

        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((len >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    static func encode(text: String) -> Data { encode(Data(text.utf8), opcode: .text) }

    struct Frame {
        var opcode: Opcode
        var payload: Data
    }

    /// Try to parse one complete frame from the front of `buffer`. On success
    /// removes the consumed bytes from `buffer` and returns the frame. Returns
    /// nil when more bytes are needed. Client frames are always masked.
    static func decodeOne(from buffer: inout Data) -> Frame? {
        guard buffer.count >= 2 else { return nil }
        let bytes = [UInt8](buffer)

        let opcodeRaw = bytes[0] & 0x0F
        let masked = (bytes[1] & 0x80) != 0
        var len = Int(bytes[1] & 0x7F)
        var offset = 2

        if len == 126 {
            guard bytes.count >= 4 else { return nil }
            len = (Int(bytes[2]) << 8) | Int(bytes[3])
            offset = 4
        } else if len == 127 {
            guard bytes.count >= 10 else { return nil }
            len = 0
            for i in 2..<10 { len = (len << 8) | Int(bytes[i]) }
            offset = 10
        }

        var maskKey: [UInt8] = [0, 0, 0, 0]
        if masked {
            guard bytes.count >= offset + 4 else { return nil }
            maskKey = Array(bytes[offset..<offset + 4])
            offset += 4
        }

        guard bytes.count >= offset + len else { return nil }
        var payload = [UInt8](bytes[offset..<offset + len])
        if masked {
            for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] }
        }

        buffer.removeSubrange(0..<(offset + len))
        let opcode = Opcode(rawValue: opcodeRaw) ?? .text
        return Frame(opcode: opcode, payload: Data(payload))
    }
}
