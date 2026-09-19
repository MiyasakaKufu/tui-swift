/// キー入力の種類。
public enum Key: Hashable, Sendable {
    /// 通常の文字。
    case character(Character)
    /// Enter。
    case enter
    /// Tab。
    case tab
    /// Shift+Tab。
    case backTab
    /// Backspace。
    case backspace
    /// Delete。
    case delete
    /// Insert。
    case insert
    /// Escape。
    case escape
    /// ↑。
    case up
    /// ↓。
    case down
    /// ←。
    case left
    /// →。
    case right
    /// Home。
    case home
    /// End。
    case end
    /// PageUp。
    case pageUp
    /// PageDown。
    case pageDown
    /// ファンクションキー（1 起点）。
    case function(Int)
    /// 解釈できなかった入力。
    case unknown
}

/// 修飾キー。
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    /// 各修飾キーをビットで表した値。
    public let rawValue: UInt8

    /// ビットの並びから修飾キーの組を作る。
    ///
    /// - Parameters:
    ///   - rawValue: 各修飾キーをビットで表した値。
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Shift。
    public static let shift = KeyModifiers(rawValue: 1 << 0)
    /// Alt（Option）。
    public static let alt = KeyModifiers(rawValue: 1 << 1)
    /// Control。
    public static let control = KeyModifiers(rawValue: 1 << 2)

    /// CSI の修飾パラメータから修飾キーの組を作る。
    ///
    /// - Parameters:
    ///   - csiParameter: CSI の修飾パラメータ（1 + ビットマスク）。1 以下なら修飾なし。
    public init(csiParameter: Int) {
        let mask = max(0, csiParameter - 1)
        var modifiers: KeyModifiers = []
        if mask & 1 != 0 { modifiers.insert(.shift) }
        if mask & 2 != 0 { modifiers.insert(.alt) }
        if mask & 4 != 0 { modifiers.insert(.control) }
        self = modifiers
    }
}

/// キーイベント。
public struct KeyEvent: Hashable, Sendable {
    /// 押されたキー。
    public var key: Key
    /// 同時に押されていた修飾キー。
    public var modifiers: KeyModifiers

    /// キーと修飾キーからイベントを作る。
    ///
    /// - Parameters:
    ///   - key: 押されたキー。
    ///   - modifiers: 同時に押されていた修飾キー。
    public init(_ key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 修飾なしの文字キーであればその文字。
    ///
    /// - Note: Shift だけが付いている場合も、文字として扱う。
    public var character: Character? {
        if case .character(let value) = key, modifiers.isEmpty || modifiers == .shift {
            return value
        }
        return nil
    }

    /// Ctrl + 指定文字かどうかを判定する。
    ///
    /// - Parameters:
    ///   - character: 組み合わせを調べる文字。
    /// - Returns: Ctrl と `character` の組み合わせなら `true`。
    public func isControl(_ character: Character) -> Bool {
        modifiers.contains(.control) && key == .character(character)
    }
}
