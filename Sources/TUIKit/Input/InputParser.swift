/// 端末から読み取ったバイト列をイベントへ変換する増分パーサ。
///
/// エスケープシーケンスが途中までしか届いていない場合は内部に保持し、
/// 続きが来たときに解釈する。
public struct InputParser {
    private var pending: [UInt8] = []
    private var isInPaste = false

    /// ブラケットペーストの終端 `ESC [ 201 ~`。
    private static let pasteTerminator: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

    public init() {}

    /// 未解釈のバイトが残っているか。
    public var hasPendingBytes: Bool { !pending.isEmpty }

    /// バイト列を流し込み、確定したイベントを取り出す。
    public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
        pending.append(contentsOf: bytes)
        var events: [InputEvent] = []

        while !pending.isEmpty {
            if isInPaste {
                guard let terminator = indexOfPasteTerminator() else { break }
                let content = Array(pending[0..<terminator])
                events.append(.paste(String(decoding: content, as: UTF8.self)))
                pending.removeFirst(terminator + InputParser.pasteTerminator.count)
                isInPaste = false
                continue
            }

            switch parseOne() {
            case .incomplete:
                return events
            case .skip(let consumed):
                pending.removeFirst(consumed)
            case .pasteStart(let consumed):
                pending.removeFirst(consumed)
                isInPaste = true
            case .event(let event, let consumed):
                pending.removeFirst(consumed)
                events.append(event)
            }
        }
        return events
    }

    /// 入力が途切れたときに呼び、単独の ESC を Escape キーとして確定させる。
    public mutating func flush() -> [InputEvent] {
        guard !isInPaste, let first = pending.first, first == 0x1B else { return [] }
        pending.removeFirst()
        var events: [InputEvent] = [.key(KeyEvent(.escape))]
        events.append(contentsOf: feed([]))
        return events
    }

    // MARK: - 解析

    private enum ParseOutcome {
        case event(InputEvent, consumed: Int)
        case skip(consumed: Int)
        case pasteStart(consumed: Int)
        case incomplete
    }

    private func indexOfPasteTerminator() -> Int? {
        let terminator = InputParser.pasteTerminator
        guard pending.count >= terminator.count else { return nil }
        let last = pending.count - terminator.count
        var start = 0
        while start <= last {
            var matched = true
            for offset in 0..<terminator.count where pending[start + offset] != terminator[offset] {
                matched = false
                break
            }
            if matched { return start }
            start += 1
        }
        return nil
    }

    private func parseOne() -> ParseOutcome {
        guard let first = pending.first else { return .incomplete }
        if first == 0x1B { return parseEscape() }
        return parseKey(at: 0, extraModifiers: [])
    }

    private func parseEscape() -> ParseOutcome {
        guard pending.count >= 2 else { return .incomplete }
        switch pending[1] {
        case 0x5B: // '['
            return parseControlSequence()
        case 0x4F: // 'O' — SS3（F1〜F4 など）
            guard pending.count >= 3 else { return .incomplete }
            switch pending[2] {
            case 0x50: return .event(.key(KeyEvent(.function(1))), consumed: 3)
            case 0x51: return .event(.key(KeyEvent(.function(2))), consumed: 3)
            case 0x52: return .event(.key(KeyEvent(.function(3))), consumed: 3)
            case 0x53: return .event(.key(KeyEvent(.function(4))), consumed: 3)
            case 0x48: return .event(.key(KeyEvent(.home)), consumed: 3)
            case 0x46: return .event(.key(KeyEvent(.end)), consumed: 3)
            default: return .skip(consumed: 3)
            }
        case 0x1B:
            // ESC が連続した場合、最初の 1 つを Escape キーとして確定する。
            return .event(.key(KeyEvent(.escape)), consumed: 1)
        default:
            return parseKey(at: 1, extraModifiers: .alt)
        }
    }

    private func parseControlSequence() -> ParseOutcome {
        var index = 2
        var isMouseSequence = false

        if index < pending.count, pending[index] == 0x3C { // '<'
            isMouseSequence = true
            index += 1
        }

        var parameterBytes: [UInt8] = []
        while index < pending.count {
            let byte = pending[index]
            if byte >= 0x30 && byte <= 0x3F {
                parameterBytes.append(byte)
                index += 1
            } else if byte >= 0x20 && byte <= 0x2F {
                index += 1
            } else if byte >= 0x40 && byte <= 0x7E {
                return interpret(
                    final: byte,
                    parameters: InputParser.parseParameters(parameterBytes),
                    isMouseSequence: isMouseSequence,
                    consumed: index + 1
                )
            } else {
                return .skip(consumed: index + 1)
            }
        }
        return .incomplete
    }

    private static func parseParameters(_ bytes: [UInt8]) -> [Int] {
        if bytes.isEmpty { return [] }
        var parameters: [Int] = []
        var current = 0
        var hasDigits = false
        for byte in bytes {
            if byte >= 0x30 && byte <= 0x39 {
                current = current * 10 + Int(byte - 0x30)
                hasDigits = true
            } else if byte == 0x3B { // ';'
                parameters.append(hasDigits ? current : 0)
                current = 0
                hasDigits = false
            }
        }
        parameters.append(hasDigits ? current : 0)
        return parameters
    }

    private func interpret(
        final: UInt8,
        parameters: [Int],
        isMouseSequence: Bool,
        consumed: Int
    ) -> ParseOutcome {
        if isMouseSequence, final == 0x4D || final == 0x6D {
            guard parameters.count >= 3 else { return .skip(consumed: consumed) }
            let event = InputParser.mouseEvent(
                code: parameters[0],
                column: parameters[1],
                row: parameters[2],
                isPress: final == 0x4D
            )
            return .event(.mouse(event), consumed: consumed)
        }

        let modifiers = KeyModifiers(csiParameter: parameters.count >= 2 ? parameters[1] : 1)

        switch final {
        case 0x41: return .event(.key(KeyEvent(.up, modifiers: modifiers)), consumed: consumed)
        case 0x42: return .event(.key(KeyEvent(.down, modifiers: modifiers)), consumed: consumed)
        case 0x43: return .event(.key(KeyEvent(.right, modifiers: modifiers)), consumed: consumed)
        case 0x44: return .event(.key(KeyEvent(.left, modifiers: modifiers)), consumed: consumed)
        case 0x48: return .event(.key(KeyEvent(.home, modifiers: modifiers)), consumed: consumed)
        case 0x46: return .event(.key(KeyEvent(.end, modifiers: modifiers)), consumed: consumed)
        case 0x5A: return .event(.key(KeyEvent(.backTab, modifiers: modifiers)), consumed: consumed)
        case 0x49: return .event(.focus(true), consumed: consumed)
        case 0x4F: return .event(.focus(false), consumed: consumed)
        case 0x75: // CSI u（Kitty キーボードプロトコル）
            guard let scalarValue = parameters.first, let scalar = Unicode.Scalar(UInt32(scalarValue)) else {
                return .skip(consumed: consumed)
            }
            return .event(.key(KeyEvent(.character(Character(scalar)), modifiers: modifiers)), consumed: consumed)
        case 0x7E: // '~'
            guard let code = parameters.first else { return .skip(consumed: consumed) }
            if code == 200 { return .pasteStart(consumed: consumed) }
            if code == 201 { return .skip(consumed: consumed) }
            guard let key = InputParser.tildeKey(code) else { return .skip(consumed: consumed) }
            return .event(.key(KeyEvent(key, modifiers: modifiers)), consumed: consumed)
        default:
            return .skip(consumed: consumed)
        }
    }

    private static func tildeKey(_ code: Int) -> Key? {
        switch code {
        case 1, 7: return .home
        case 2: return .insert
        case 3: return .delete
        case 4, 8: return .end
        case 5: return .pageUp
        case 6: return .pageDown
        case 11...15: return .function(code - 10)
        case 17...21: return .function(code - 11)
        case 23, 24: return .function(code - 12)
        default: return nil
        }
    }

    private static func mouseEvent(code: Int, column: Int, row: Int, isPress: Bool) -> MouseEvent {
        var modifiers: KeyModifiers = []
        if code & 4 != 0 { modifiers.insert(.shift) }
        if code & 8 != 0 { modifiers.insert(.alt) }
        if code & 16 != 0 { modifiers.insert(.control) }

        let position = Point(x: max(0, column - 1), y: max(0, row - 1))

        if code & 64 != 0 {
            let action: MouseAction = (code & 1) == 0 ? .scrollUp : .scrollDown
            return MouseEvent(position: position, button: .none, action: action, modifiers: modifiers)
        }

        let button: MouseButton
        switch code & 3 {
        case 0: button = .left
        case 1: button = .middle
        case 2: button = .right
        default: button = .none
        }

        let action: MouseAction
        if code & 32 != 0 {
            action = .drag
        } else {
            action = isPress ? .press : .release
        }
        return MouseEvent(position: position, button: button, action: action, modifiers: modifiers)
    }

    private func parseKey(at start: Int, extraModifiers: KeyModifiers) -> ParseOutcome {
        guard start < pending.count else { return .incomplete }
        let byte = pending[start]
        var modifiers = extraModifiers

        switch byte {
        case 0x0D, 0x0A:
            return .event(.key(KeyEvent(.enter, modifiers: modifiers)), consumed: start + 1)
        case 0x09:
            return .event(.key(KeyEvent(.tab, modifiers: modifiers)), consumed: start + 1)
        case 0x7F:
            return .event(.key(KeyEvent(.backspace, modifiers: modifiers)), consumed: start + 1)
        case 0x00:
            modifiers.insert(.control)
            return .event(.key(KeyEvent(.character(" "), modifiers: modifiers)), consumed: start + 1)
        case 0x01...0x1A:
            modifiers.insert(.control)
            let letter = Character(Unicode.Scalar(byte + 0x60))
            return .event(.key(KeyEvent(.character(letter), modifiers: modifiers)), consumed: start + 1)
        case 0x1C...0x1F:
            modifiers.insert(.control)
            let letter = Character(Unicode.Scalar(byte + 0x40))
            return .event(.key(KeyEvent(.character(letter), modifiers: modifiers)), consumed: start + 1)
        case 0x20...0x7E:
            let character = Character(Unicode.Scalar(byte))
            return .event(.key(KeyEvent(.character(character), modifiers: modifiers)), consumed: start + 1)
        default:
            let length = InputParser.utf8SequenceLength(byte)
            guard length > 0 else { return .skip(consumed: start + 1) }
            guard start + length <= pending.count else { return .incomplete }
            let scalarBytes = Array(pending[start..<(start + length)])
            let decoded = String(decoding: scalarBytes, as: UTF8.self)
            guard let character = decoded.first, character != "\u{FFFD}" else {
                return .skip(consumed: start + length)
            }
            return .event(.key(KeyEvent(.character(character), modifiers: modifiers)), consumed: start + length)
        }
    }

    private static func utf8SequenceLength(_ leadingByte: UInt8) -> Int {
        switch leadingByte {
        case 0xC2...0xDF: return 2
        case 0xE0...0xEF: return 3
        case 0xF0...0xF4: return 4
        default: return 0
        }
    }
}
