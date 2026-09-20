/// マウスイベントを受け取る範囲。
public enum MouseTracking: Hashable, Sendable {
    /// 受け取らない。
    case disabled
    /// ボタンの押下・解放・ドラッグとホイールを受け取る。
    case buttons
    /// ボタンを押していない間の移動（`.move`）も受け取る。
    ///
    /// - Note: カーソルが 1 桁動くたびにイベントが届く。ホバーの強調やツールチップのように、
    ///   移動そのものを使うアプリだけが選ぶ。
    case motion
}

/// マウスボタン。
public enum MouseButton: Hashable, Sendable {
    /// 左ボタン。
    case left
    /// 中ボタン。
    case middle
    /// 右ボタン。
    case right
    /// 拡張ボタン 8（「戻る」に割り当てられることが多い）。
    case backward
    /// 拡張ボタン 9（「進む」に割り当てられることが多い）。
    case forward
    /// 拡張ボタン 10。
    case button10
    /// 拡張ボタン 11。
    case button11
    /// ボタンを伴わない（ホイール操作など）。
    case none
}

/// マウス操作の種類。
public enum MouseAction: Hashable, Sendable {
    /// ボタンを押した。
    case press
    /// ボタンを離した。
    case release
    /// ボタンを押したまま動かした。
    case drag
    /// ボタンを押さずに動かした。
    case move
    /// ホイールを上へ回した。
    case scrollUp
    /// ホイールを下へ回した。
    case scrollDown
    /// ホイールを左へ倒した。
    case scrollLeft
    /// ホイールを右へ倒した。
    case scrollRight
}

/// マウスイベント。座標は 0 起点。
public struct MouseEvent: Hashable, Sendable {
    /// 操作された位置。
    public var position: Point
    /// 操作されたボタン。
    public var button: MouseButton
    /// 操作の種類。
    public var action: MouseAction
    /// 同時に押されていた修飾キー。
    public var modifiers: KeyModifiers

    /// 位置・ボタン・操作からイベントを作る。
    ///
    /// - Parameters:
    ///   - position: 操作された位置。
    ///   - button: 操作されたボタン。
    ///   - action: 操作の種類。
    ///   - modifiers: 同時に押されていた修飾キー。
    public init(position: Point, button: MouseButton, action: MouseAction, modifiers: KeyModifiers = []) {
        self.position = position
        self.button = button
        self.action = action
        self.modifiers = modifiers
    }
}

/// 端末から届くイベント。
public enum InputEvent: Hashable, Sendable {
    /// キーが押された。
    case key(KeyEvent)
    /// マウスが操作された。
    case mouse(MouseEvent)
    /// ウィンドウサイズが変わった。
    case resize(Size)
    /// ブラケットペーストで貼り付けられた文字列。
    case paste(String)
    /// 端末のフォーカス変化（`true` で獲得）。
    case focus(Bool)
}
