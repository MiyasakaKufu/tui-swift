/// キー入力の種類。
public enum Key: Hashable, Sendable {
    /// 通常の文字。
    case character(Character)
    case enter
    case tab
    case backTab
    case backspace
    case delete
    case insert
    case escape
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    /// ファンクションキー（1 起点）。
    case function(Int)
    /// 解釈できなかった入力。
    case unknown
}

/// 修飾キー。
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let alt = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)

    /// CSI の修飾パラメータ（1 + ビットマスク）から生成する。
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
    public var key: Key
    public var modifiers: KeyModifiers

    public init(_ key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 修飾なしの文字キーであればその文字を返す。
    public var character: Character? {
        if case .character(let value) = key, modifiers.isEmpty || modifiers == .shift {
            return value
        }
        return nil
    }

    /// Ctrl + 指定文字かどうか。
    public func isControl(_ character: Character) -> Bool {
        modifiers.contains(.control) && key == .character(character)
    }
}
