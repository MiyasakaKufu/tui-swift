/// 端末から読み取ったバイト列をイベントへ変換する増分パーサ。
///
/// エスケープシーケンスが途中までしか届いていない場合は内部に保持し、
/// 続きが来たときに解釈する。
public struct InputParser {
    private var pending: [UInt8] = []
    private var isInPaste = false
    private var replies: [TerminalReply] = []

    /// ブラケットペーストの終端 `ESC [ 201 ~`。
    private static let pasteTerminator: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

    /// 単独の ESC の続きを待つ時間（秒）。
    private static let escapeWaitDuration = 0.05

    /// 始まりだけが届いた制御コードの続きを待つ時間（秒）。
    private static let sequenceWaitDuration = 1.0

    /// 何も読み取っていないパーサを作る。
    public init() {}

    /// 未解釈のバイトが残っているか。
    public var hasPendingBytes: Bool { !pending.isEmpty }

    /// 未解釈のバイトの続きを待つ時間（秒）。
    ///
    /// この時間が過ぎても続きが届かなければ `flush()` を呼んでよい。
    /// 待っても確定できるものがないときは `nil`。
    public var pendingWaitDuration: Double? {
        guard !isInPaste, let first = pending.first, first == 0x1B else { return nil }
        return pending.count == 1 ? InputParser.escapeWaitDuration : InputParser.sequenceWaitDuration
    }

    /// バイト列を流し込み、確定したイベントを取り出す。
    ///
    /// - Parameters:
    ///   - bytes: 端末から読み取ったバイト列。
    /// - Returns: 確定したイベント。途中までのエスケープシーケンスは内部に残る。
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
            case .reply(let reply, let consumed):
                pending.removeFirst(consumed)
                replies.append(reply)
            }
        }
        return events
    }

    /// 溜まっている端末の応答を取り出す。
    ///
    /// - Returns: `feed(_:)` が読み取った応答。取り出した分は内部から消える。
    public mutating func takeReplies() -> [TerminalReply] {
        let taken = replies
        replies.removeAll()
        return taken
    }

    /// 入力が途切れたときに呼び、ESC で始まる未解釈のバイトを捨てるか確定させる。
    ///
    /// 単独の ESC は Escape キー、`ESC [` と `ESC O` は Alt+[ と Alt+O になる。
    /// それより長い、途中までの制御コードは捨てる。
    ///
    /// - Returns: 確定したイベント。確定するものがなければ空配列。
    /// - Postcondition: ESC で始まる未解釈のバイトは残らない。
    public mutating func flush() -> [InputEvent] {
        guard !isInPaste, let first = pending.first, first == 0x1B else { return [] }
        if pending.count == 1 {
            pending.removeFirst()
            return [.key(KeyEvent(.escape))]
        }

        // 途中までの制御コードを 1 バイトずつキーにしてはいけない。
        // 続きが届いてももう制御コードとして読めず、`ESC [ < 65 ; 10` が Escape と文字の列になる。
        var events: [InputEvent] = []
        if pending.count == 2, pending[1] == 0x5B || pending[1] == 0x4F {
            // Alt+[ と Alt+O は `ESC [` / `ESC O` として届き、CSI / SS3 の始まりと同じ形になる。
            let character = Character(Unicode.Scalar(pending[1]))
            events.append(.key(KeyEvent(.character(character), modifiers: .alt)))
        }
        pending.removeAll()
        return events
    }

    // MARK: - 解析

    private enum ParseOutcome {
        case event(InputEvent, consumed: Int)
        case reply(TerminalReply, consumed: Int)
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
        var prefix: UInt8?

        if index < pending.count, pending[index] >= 0x3C, pending[index] <= 0x3F { // '<' '=' '>' '?'
            prefix = pending[index]
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
                    parameters: Parameters(parameterBytes),
                    prefix: prefix,
                    consumed: index + 1
                )
            } else {
                return .skip(consumed: index + 1)
            }
        }
        return .incomplete
    }

    /// `CSI` のパラメータ。
    ///
    /// `;` で区切られたパラメータが並び、それぞれが `:` で下位パラメータへ分かれる。
    private struct Parameters {
        private var groups: [[Int]] = []

        /// パラメータのバイト列を解析して作る。
        ///
        /// - Parameters:
        ///   - bytes: 前置きの記号と最終バイトの間にあるバイト列。
        init(_ bytes: [UInt8]) {
            guard !bytes.isEmpty else { return }

            var group: [Int] = []
            var current = 0
            var hasDigits = false
            for byte in bytes {
                switch byte {
                case 0x30...0x39:
                    current = current * 10 + Int(byte - 0x30)
                    hasDigits = true
                case 0x3A: // ':'
                    group.append(hasDigits ? current : 0)
                    current = 0
                    hasDigits = false
                case 0x3B: // ';'
                    group.append(hasDigits ? current : 0)
                    groups.append(group)
                    group = []
                    current = 0
                    hasDigits = false
                default:
                    break
                }
            }
            group.append(hasDigits ? current : 0)
            groups.append(group)
        }

        /// 指定した位置のパラメータ。無ければ `nil`。
        ///
        /// - Parameters:
        ///   - index: 取り出す位置。0 起点。
        subscript(index: Int) -> Int? { self[index, 0] }

        /// 指定した位置のパラメータの、指定した位置の下位パラメータ。無ければ `nil`。
        ///
        /// - Parameters:
        ///   - index: 取り出すパラメータの位置。0 起点。
        ///   - subIndex: 取り出す下位パラメータの位置。0 起点。
        subscript(index: Int, subIndex: Int) -> Int? {
            guard index >= 0, index < groups.count else { return nil }
            guard subIndex >= 0, subIndex < groups[index].count else { return nil }
            return groups[index][subIndex]
        }
    }

    private func interpret(
        final: UInt8,
        parameters: Parameters,
        prefix: UInt8?,
        consumed: Int
    ) -> ParseOutcome {
        if let prefix {
            return interpretPrivateSequence(
                final: final,
                parameters: parameters,
                prefix: prefix,
                consumed: consumed
            )
        }

        let modifiers = KeyModifiers(csiParameter: parameters[1] ?? 1)

        switch final {
        case 0x41: return .event(.key(KeyEvent(.up, modifiers: modifiers)), consumed: consumed)
        case 0x42: return .event(.key(KeyEvent(.down, modifiers: modifiers)), consumed: consumed)
        case 0x43: return .event(.key(KeyEvent(.right, modifiers: modifiers)), consumed: consumed)
        case 0x44: return .event(.key(KeyEvent(.left, modifiers: modifiers)), consumed: consumed)
        case 0x48: return .event(.key(KeyEvent(.home, modifiers: modifiers)), consumed: consumed)
        case 0x46: return .event(.key(KeyEvent(.end, modifiers: modifiers)), consumed: consumed)
        case 0x5A: return .event(.key(KeyEvent(.backTab, modifiers: modifiers)), consumed: consumed)
        case 0x50, 0x51, 0x52, 0x53: // 'P'〜'S' — 修飾キー付きの F1〜F4
            // `CSI 1;2R`（Shift+F3）はカーソル位置の問い合わせへの応答と同じ形だが、
            // TUIKit はカーソル位置（`CSI 6 n`）を問い合わせないので F3 として扱う。
            let number = Int(final - 0x4F)
            return .event(.key(KeyEvent(.function(number), modifiers: modifiers)), consumed: consumed)
        case 0x49: return .event(.focus(true), consumed: consumed)
        case 0x4F: return .event(.focus(false), consumed: consumed)
        case 0x75: // 'u' — kitty keyboard protocol のキー
            // 修飾キーのパラメータに続く下位パラメータはイベント種別で、3 はキーを離した通知。
            // 押したときと同じキーになるため、そのまま返すと 1 回の打鍵が 2 つ届く。
            if parameters[1, 1] == 3 { return .skip(consumed: consumed) }
            guard let code = parameters[0], let key = InputParser.keyboardProtocolKey(code) else {
                return .skip(consumed: consumed)
            }
            // Shift+Tab は従来 `CSI Z` として届き、Shift の付かない `.backTab` になる。
            // 同じ打鍵がプロトコルの有無で別のキーになってはいけない。
            if key == .tab, modifiers.contains(.shift) {
                var rest = modifiers
                rest.remove(.shift)
                return .event(.key(KeyEvent(.backTab, modifiers: rest)), consumed: consumed)
            }
            return .event(.key(KeyEvent(key, modifiers: modifiers)), consumed: consumed)
        case 0x7E: // '~'
            guard let code = parameters[0] else { return .skip(consumed: consumed) }
            if code == 200 { return .pasteStart(consumed: consumed) }
            if code == 201 { return .skip(consumed: consumed) }
            guard let key = InputParser.tildeKey(code) else { return .skip(consumed: consumed) }
            return .event(.key(KeyEvent(key, modifiers: modifiers)), consumed: consumed)
        default:
            return .skip(consumed: consumed)
        }
    }

    /// 前置きの記号が付いた `CSI` を解釈する。
    ///
    /// - Parameters:
    ///   - final: 制御コードの最終バイト。
    ///   - parameters: 最終バイトの前にあるパラメータ。
    ///   - prefix: `CSI` の直後にある前置きの記号。
    ///   - consumed: この制御コードが使うバイト数。
    /// - Returns: 解釈の結果。知らない組み合わせは読み飛ばす。
    private func interpretPrivateSequence(
        final: UInt8,
        parameters: Parameters,
        prefix: UInt8,
        consumed: Int
    ) -> ParseOutcome {
        switch (prefix, final) {
        case (0x3C, 0x4D), (0x3C, 0x6D): // '<' と 'M' / 'm' — SGR 拡張形式のマウス
            guard let code = parameters[0], let column = parameters[1], let row = parameters[2] else {
                return .skip(consumed: consumed)
            }
            let event = InputParser.mouseEvent(
                code: code,
                column: column,
                row: row,
                isPress: final == 0x4D
            )
            return .event(.mouse(event), consumed: consumed)
        case (0x3F, 0x75): // '?' と 'u' — kitty keyboard protocol の対応状況
            return .reply(.keyboardProtocol(flags: parameters[0] ?? 0), consumed: consumed)
        case (0x3F, 0x63): // '?' と 'c' — 装置属性
            return .reply(.deviceAttributes, consumed: consumed)
        default:
            return .skip(consumed: consumed)
        }
    }

    /// kitty keyboard protocol のキーコードをキーへ変換する。
    ///
    /// - Parameters:
    ///   - code: `CSI <code> ... u` の先頭パラメータ。
    /// - Returns: 対応するキー。当てはまるキーがなければ `nil`。
    private static func keyboardProtocolKey(_ code: Int) -> Key? {
        switch code {
        case 9: return .tab
        case 13, 57414: return .enter // 57414 はテンキーの Enter。
        case 27: return .escape
        case 127: return .backspace
        case 57376...57398: return .function(code - 57376 + 13) // F13〜F35。
        case 57399...57408: return .character(Character(Unicode.Scalar(UInt8(code - 57399 + 0x30)))) // テンキーの 0〜9。
        case 57409: return .character(".")
        case 57410: return .character("/")
        case 57411: return .character("*")
        case 57412: return .character("-")
        case 57413: return .character("+")
        case 57415: return .character("=")
        case 57416: return .character(",")
        case 57417: return .left
        case 57418: return .right
        case 57419: return .up
        case 57420: return .down
        case 57421: return .pageUp
        case 57422: return .pageDown
        case 57423: return .home
        case 57424: return .end
        case 57425: return .insert
        case 57426: return .delete
        default:
            // 57344（U+E000）以降は私用領域で、キーコードとしての意味しかない。
            // Caps Lock や修飾キー単独の通知がここへ来るので、文字にしてはいけない。
            guard code > 0, code < 57344, let scalar = Unicode.Scalar(UInt32(code)) else { return nil }
            return .character(Character(scalar))
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

        // ビット 128（拡張ボタン）→ ビット 64（ホイール）→ 下位 2 ビット（通常ボタン）の順に判定する。
        // ビット 128 を先に見ないと、拡張ボタンを左・中・右ボタンと誤認する。
        let button: MouseButton
        if code & 128 != 0 {
            switch code & 3 {
            case 0: button = .backward
            case 1: button = .forward
            case 2: button = .button10
            default: button = .button11
            }
        } else if code & 64 != 0 {
            let action: MouseAction
            switch code & 3 {
            case 0: action = .scrollUp
            case 1: action = .scrollDown
            case 2: action = .scrollLeft
            default: action = .scrollRight
            }
            return MouseEvent(position: position, button: .none, action: action, modifiers: modifiers)
        } else {
            switch code & 3 {
            case 0: button = .left
            case 1: button = .middle
            case 2: button = .right
            default: button = .none
            }
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
