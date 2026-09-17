/// マウスボタン。
public enum MouseButton: Hashable, Sendable {
    case left
    case middle
    case right
    case none
}

/// マウス操作の種類。
public enum MouseAction: Hashable, Sendable {
    case press
    case release
    case drag
    case scrollUp
    case scrollDown
}

/// マウスイベント。座標は 0 起点。
public struct MouseEvent: Hashable, Sendable {
    public var position: Point
    public var button: MouseButton
    public var action: MouseAction
    public var modifiers: KeyModifiers

    public init(position: Point, button: MouseButton, action: MouseAction, modifiers: KeyModifiers = []) {
        self.position = position
        self.button = button
        self.action = action
        self.modifiers = modifiers
    }
}

/// 端末から届くイベント。
public enum InputEvent: Hashable, Sendable {
    case key(KeyEvent)
    case mouse(MouseEvent)
    /// ウィンドウサイズが変わった。
    case resize(Size)
    /// ブラケットペーストで貼り付けられた文字列。
    case paste(String)
    /// 端末のフォーカス変化（`true` で獲得）。
    case focus(Bool)
}
