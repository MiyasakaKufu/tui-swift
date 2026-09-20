/// バイト列を Base64（RFC 4648）の文字列へ変換する。
enum Base64 {

    /// 6 ビットの値に対応する文字。RFC 4648 の標準アルファベット。
    private static let alphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
    )

    private static let padding = UInt8(ascii: "=")

    /// バイト列を Base64 の文字列へ変換する。
    ///
    /// - Parameters:
    ///   - bytes: 変換するバイト列。
    /// - Returns: Base64 の文字列。端数は `=` で埋める。
    static func encode(_ bytes: [UInt8]) -> String {
        var encoded: [UInt8] = []
        encoded.reserveCapacity((bytes.count + 2) / 3 * 4)

        var index = 0
        while index + 2 < bytes.count {
            let group = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            encoded.append(alphabet[(group >> 18) & 0x3F])
            encoded.append(alphabet[(group >> 12) & 0x3F])
            encoded.append(alphabet[(group >> 6) & 0x3F])
            encoded.append(alphabet[group & 0x3F])
            index += 3
        }

        switch bytes.count - index {
        case 1:
            let group = Int(bytes[index]) << 16
            encoded.append(alphabet[(group >> 18) & 0x3F])
            encoded.append(alphabet[(group >> 12) & 0x3F])
            encoded.append(padding)
            encoded.append(padding)
        case 2:
            let group = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8
            encoded.append(alphabet[(group >> 18) & 0x3F])
            encoded.append(alphabet[(group >> 12) & 0x3F])
            encoded.append(alphabet[(group >> 6) & 0x3F])
            encoded.append(padding)
        default:
            break
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    /// 文字列を UTF-8 のバイト列とみなして Base64 の文字列へ変換する。
    ///
    /// - Parameters:
    ///   - text: 変換する文字列。
    /// - Returns: Base64 の文字列。
    static func encode(_ text: String) -> String {
        encode(Array(text.utf8))
    }
}
