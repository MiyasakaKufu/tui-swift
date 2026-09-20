/// 端末から読み取ったバイト列をイベントへ変換する増分パーサ。
///
/// エスケープシーケンスが途中までしか届いていない場合は内部に保持し、
/// 続きが来たときに解釈する。
public struct InputParser {
    private var pending: [UInt8] = []
    private var isInPaste = false
    private var replies: [TerminalReply] = []

    /// ブラケットペーストの終端。
    private static let pasteTerminator = Array((ANSI.csi + "201~").utf8)

    /// 単独の ESC の続きを待つ時間（秒）。
    private static let escapeWaitDuration = 0.05

    /// 始まりだけが届いた制御コードの続きを待つ時間（秒）。
    private static let sequenceWaitDuration = 1.0

    /// kitty keyboard protocol が機能キーに使う、私用領域の先頭のキーコード。
    private static let firstFunctionalKeyCode = 0xE000

    /// kitty keyboard protocol で、キーを離したことを表すイベント種別。
    private static let keyReleaseEventType = 3

    /// SGR 形式のマウス報告で、動かしながらの操作であることを表すビット。
    ///
    /// ボタンを押していない間の移動は、このビットとボタンなし（下位 2 ビットが 3）の
    /// 組み合わせで届く。押したままの移動は、このビットと押しているボタンの番号で届く。
    ///
    /// - See: [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html) の「Mouse Tracking」。
    private static let mouseMotionBit = 32

    /// 何も読み取っていないパーサを作る。
    public init() {}

    /// 未解釈のバイトが残っているか。
    public var hasPendingBytes: Bool { !pending.isEmpty }

    /// 未解釈のバイトの続きを待つ時間（秒）。
    ///
    /// この時間が過ぎても続きが届かなければ `flush()` を呼んでよい。
    /// 待っても確定できるものがないときは `nil`。
    public var pendingWaitDuration: Double? {
        guard !isInPaste, let first = pending.first, first == ControlByte.escape else { return nil }
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
        guard !isInPaste, let first = pending.first, first == ControlByte.escape else { return [] }
        if pending.count == 1 {
            pending.removeFirst()
            return [.key(KeyEvent(.escape))]
        }

        // 途中までの制御コードを 1 バイトずつキーにしてはいけない。
        // 続きが届いてももう制御コードとして読めず、`ESC [ < 65 ; 10` が Escape と文字の列になる。
        var events: [InputEvent] = []
        if pending.count == 2, pending[1] == UInt8(ascii: "[") || pending[1] == UInt8(ascii: "O") {
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
        if first == ControlByte.escape { return parseEscape() }
        return parseKey(at: 0, extraModifiers: [])
    }

    private func parseEscape() -> ParseOutcome {
        guard pending.count >= 2 else { return .incomplete }
        switch pending[1] {
        case UInt8(ascii: "["):
            return parseControlSequence()
        // `ESC O` は SS3。F1〜F4 は修飾キーが付かないときだけこの形で届く。
        case UInt8(ascii: "O"):
            guard pending.count >= 3 else { return .incomplete }
            switch pending[2] {
            case UInt8(ascii: "P"): return .event(.key(KeyEvent(.function(1))), consumed: 3)
            case UInt8(ascii: "Q"): return .event(.key(KeyEvent(.function(2))), consumed: 3)
            case UInt8(ascii: "R"): return .event(.key(KeyEvent(.function(3))), consumed: 3)
            case UInt8(ascii: "S"): return .event(.key(KeyEvent(.function(4))), consumed: 3)
            case UInt8(ascii: "H"): return .event(.key(KeyEvent(.home)), consumed: 3)
            case UInt8(ascii: "F"): return .event(.key(KeyEvent(.end)), consumed: 3)
            default: return .skip(consumed: 3)
            }
        case ControlByte.escape:
            // ESC が連続した場合、最初の 1 つを Escape キーとして確定する。
            return .event(.key(KeyEvent(.escape)), consumed: 1)
        default:
            return parseKey(at: 1, extraModifiers: .alt)
        }
    }

    private func parseControlSequence() -> ParseOutcome {
        var index = 2
        var prefix: UInt8?

        if index < pending.count, ControlByte.privatePrefixes.contains(pending[index]) {
            prefix = pending[index]
            index += 1
        }

        var parameterBytes: [UInt8] = []
        while index < pending.count {
            let byte = pending[index]
            switch byte {
            case ControlByte.parameterBytes:
                parameterBytes.append(byte)
                index += 1
            case ControlByte.intermediateBytes:
                index += 1
            case ControlByte.finalBytes:
                return interpret(
                    final: byte,
                    parameters: Parameters(parameterBytes),
                    prefix: prefix,
                    consumed: index + 1
                )
            default:
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
                case UInt8(ascii: "0")...UInt8(ascii: "9"):
                    current = current * 10 + Int(byte - UInt8(ascii: "0"))
                    hasDigits = true
                case UInt8(ascii: ":"):
                    group.append(hasDigits ? current : 0)
                    current = 0
                    hasDigits = false
                case UInt8(ascii: ";"):
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
        case UInt8(ascii: "A"): return .event(.key(KeyEvent(.up, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "B"): return .event(.key(KeyEvent(.down, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "C"): return .event(.key(KeyEvent(.right, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "D"): return .event(.key(KeyEvent(.left, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "H"): return .event(.key(KeyEvent(.home, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "F"): return .event(.key(KeyEvent(.end, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "Z"): return .event(.key(KeyEvent(.backTab, modifiers: modifiers)), consumed: consumed)
        // 修飾キーが付くと、F1〜F4 は SS3 ではなく `CSI` で届く。
        case UInt8(ascii: "P")...UInt8(ascii: "S"):
            // `CSI 1;2R`（Shift+F3）はカーソル位置の問い合わせへの応答と同じ形だが、
            // TUIKit はカーソル位置（`CSI 6 n`）を問い合わせないので F3 として扱う。
            let number = Int(final - UInt8(ascii: "P")) + 1
            return .event(.key(KeyEvent(.function(number), modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "I"): return .event(.focus(true), consumed: consumed)
        case UInt8(ascii: "O"): return .event(.focus(false), consumed: consumed)
        case UInt8(ascii: "u"):
            // 捨てないと、1 回の打鍵が押下と解放の 2 つのキーになる。
            if parameters[1, 1] == InputParser.keyReleaseEventType {
                return .skip(consumed: consumed)
            }
            guard let code = parameters[0], let key = InputParser.keyboardProtocolKey(code) else {
                return .skip(consumed: consumed)
            }
            // Shift+Tab は従来 `CSI Z` として届き、Shift の付かない `.backTab` になる。
            // `.tab` + Shift のまま返すと、アプリが同じ打鍵に 2 通りの判定を書くことになる。
            if key == .tab, modifiers.contains(.shift) {
                var rest = modifiers
                rest.remove(.shift)
                return .event(.key(KeyEvent(.backTab, modifiers: rest)), consumed: consumed)
            }
            return .event(.key(KeyEvent(key, modifiers: modifiers)), consumed: consumed)
        case UInt8(ascii: "~"):
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
        case (UInt8(ascii: "<"), UInt8(ascii: "M")), (UInt8(ascii: "<"), UInt8(ascii: "m")):
            guard let code = parameters[0], let column = parameters[1], let row = parameters[2] else {
                return .skip(consumed: consumed)
            }
            let event = InputParser.mouseEvent(
                code: code,
                column: column,
                row: row,
                isPress: final == UInt8(ascii: "M")
            )
            return .event(.mouse(event), consumed: consumed)
        case (UInt8(ascii: "?"), UInt8(ascii: "u")):
            return .reply(.keyboardProtocol(flags: parameters[0] ?? 0), consumed: consumed)
        case (UInt8(ascii: "?"), UInt8(ascii: "c")):
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
        case 13, 57414: return .enter
        case 27: return .escape
        case 127: return .backspace
        case 57376...57398: return .function(code - 57376 + 13)
        case 57399...57408: return .character(Character(Unicode.Scalar(UInt8(code - 57399) + UInt8(ascii: "0"))))
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
            guard code > 0, code < InputParser.firstFunctionalKeyCode,
                  let scalar = Unicode.Scalar(UInt32(code))
            else { return nil }
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
        if code & InputParser.mouseMotionBit != 0 {
            action = button == .none ? .move : .drag
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
        case ControlByte.carriageReturn, ControlByte.lineFeed:
            return .event(.key(KeyEvent(.enter, modifiers: modifiers)), consumed: start + 1)
        case ControlByte.horizontalTab:
            return .event(.key(KeyEvent(.tab, modifiers: modifiers)), consumed: start + 1)
        case ControlByte.delete:
            return .event(.key(KeyEvent(.backspace, modifiers: modifiers)), consumed: start + 1)
        case ControlByte.null:
            modifiers.insert(.control)
            return .event(.key(KeyEvent(.character(" "), modifiers: modifiers)), consumed: start + 1)
        case ControlByte.controlLetters:
            modifiers.insert(.control)
            let offset = byte - ControlByte.controlLetters.lowerBound
            let letter = Character(Unicode.Scalar(UInt8(ascii: "a") + offset))
            return .event(.key(KeyEvent(.character(letter), modifiers: modifiers)), consumed: start + 1)
        case ControlByte.controlSymbols:
            modifiers.insert(.control)
            let offset = byte - ControlByte.controlSymbols.lowerBound
            let letter = Character(Unicode.Scalar(UInt8(ascii: "\\") + offset))
            return .event(.key(KeyEvent(.character(letter), modifiers: modifiers)), consumed: start + 1)
        case UInt8(ascii: " ")...UInt8(ascii: "~"):
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

/// 制御コードを組み立てるバイト。
private enum ControlByte {
    static let null: UInt8 = 0x00
    static let horizontalTab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let escape: UInt8 = 0x1B
    static let delete: UInt8 = 0x7F

    /// Ctrl+A〜Ctrl+Z が届くバイト。
    static let controlLetters: ClosedRange<UInt8> = 0x01...0x1A
    /// Ctrl+\ 〜 Ctrl+_ が届くバイト。
    static let controlSymbols: ClosedRange<UInt8> = 0x1C...0x1F

    // 以下の区分は ECMA-48 5.4 による。
    static let privatePrefixes: ClosedRange<UInt8> = 0x3C...0x3F
    static let parameterBytes: ClosedRange<UInt8> = 0x30...0x3F
    static let intermediateBytes: ClosedRange<UInt8> = 0x20...0x2F
    static let finalBytes: ClosedRange<UInt8> = 0x40...0x7E
}
