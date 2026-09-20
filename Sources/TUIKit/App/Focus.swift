/// フォーカスを受け取れるもの。
///
/// フォーカスが当たるのは、描画のたびに作り直される `View` ではなく、アプリが持ち続ける
/// 状態オブジェクトのほう。`ListState` と `TextFieldState` は適合済み。
public protocol FocusTarget: AnyObject {

    /// 配送されたイベントを処理する。
    ///
    /// - Parameters:
    ///   - event: 配送されたイベント。
    /// - Returns: 処理したら `true`。`false` ならルートの `Component` へ渡る。
    func handle(_ event: InputEvent) -> Bool

    /// 端末カーソルを置きたい位置。`nil` ならカーソルを隠す。
    var cursorPosition: Point? { get }
}

extension FocusTarget {
    /// カーソルを置かない。
    public var cursorPosition: Point? { nil }
}

/// フォーカスを保ち、キーとマウスを該当するウィジェットへ配送する。
///
/// アプリはウィジェットを `View.focusable(_:in:)` で登録し、この型を `Component.focus`
/// から返す。`Application` はイベントをまずここへ渡し、処理されなかったぶんだけ
/// `Component.handle(_:)` へ渡す。
///
///     @main
///     final class Editor: TerminalApp {
///         private let manager = FocusManager()
///         private let name = TextFieldState()
///         private let note = TextFieldState()
///
///         var focus: FocusManager? { manager }
///
///         var body: some View {
///             VStack(spacing: 1) {
///                 TextField(state: name).focusable(name, in: manager)
///                 TextField(state: note).focusable(note, in: manager)
///             }
///         }
///     }
///
/// - Note: 登録は描画のたびにやり直される。Tab が巡る順序も、当たり判定の重なり順も
///   描画順で決まる。画面に出ていないウィジェットは登録されないため、フォーカスも当たり判定も
///   受け取らない。
public final class FocusManager {

    /// 登録された対象 1 つ分。
    private struct Entry {
        /// 登録された対象。
        let target: FocusTarget
        /// 直前の描画で占めた矩形。
        var rect: Rect
    }

    /// 直前の描画で登録された対象。描画順に並ぶ。
    private var entries: [Entry] = []
    /// 組み立て中の描画で登録された対象。
    private var pending: [Entry] = []
    /// 描画の最中か。
    private var isCollecting = false

    /// いまフォーカスされている対象。まだどこにもなければ `nil`。
    public private(set) var focusedTarget: FocusTarget?

    /// 端で Tab を押したとき、反対の端へ回り込むか。
    public var wrapsAround = true

    /// フォーカスがどこにもないとき、描画のたびに最初の対象へ移すか。
    ///
    /// - Note: 無効にすると、起動直後やフォーカス中のウィジェットが消えた後は、
    ///   Tab かクリック、`focus(_:)` があるまでキーがルートへ流れる。
    public var focusesFirstAutomatically = true

    /// 空のフォーカス管理を作る。
    public init() {}

    /// フォーカス中のウィジェットが端末カーソルを置きたい位置。
    public var cursorPosition: Point? { focusedTarget?.cursorPosition }

    /// 対象がフォーカスされているか。
    ///
    /// - Parameters:
    ///   - target: 調べる対象。
    /// - Returns: フォーカスされていれば `true`。
    /// - Note: 枠線の色を変えるなど、フォーカスの有無を描画へ反映するために使う。
    public func isFocused(_ target: FocusTarget) -> Bool {
        focusedTarget === target
    }

    /// フォーカスを指定した対象へ移す。
    ///
    /// - Parameters:
    ///   - target: フォーカスを移す先。`nil` ならフォーカスを外す。
    /// - Note: まだ描画していない対象も指定できる。
    public func focus(_ target: FocusTarget?) {
        focusedTarget = target
    }

    /// フォーカスを次の対象へ移す。
    ///
    /// - Returns: 移したら `true`。移せる対象がなければ `false`。
    @discardableResult
    public func focusNext() -> Bool {
        move(by: 1)
    }

    /// フォーカスを前の対象へ移す。
    ///
    /// - Returns: 移したら `true`。移せる対象がなければ `false`。
    @discardableResult
    public func focusPrevious() -> Bool {
        move(by: -1)
    }

    /// イベントをフォーカス中の、またはマウスの下にあるウィジェットへ配送する。
    ///
    /// - Parameters:
    ///   - event: 端末から届いたイベント。
    /// - Returns: フォーカスを動かしたか、配送先が処理したら `true`。
    /// - Note: Tab と Shift+Tab（`.backTab`）はフォーカス中のウィジェットへ渡さず、常に移動に使う。
    ///   `.resize` と `.focus` はウィジェットではなくアプリ全体に関わるため配送しない。
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .key(let keyEvent):
            if let moved = moveFocus(for: keyEvent) { return moved }
            return focusedTarget?.handle(event) ?? false
        case .paste:
            return focusedTarget?.handle(event) ?? false
        case .mouse(let mouseEvent):
            return deliver(mouseEvent)
        case .resize, .focus:
            return false
        }
    }

    /// 対象を、この描画で占めた矩形とともに登録する。
    ///
    /// - Parameters:
    ///   - target: 登録する対象。
    ///   - rect: この描画で占めた矩形。マウスの当たり判定に使う。
    /// - Note: 描画の最中にだけ効く。`View.focusable(_:in:)` が描画のたびに呼ぶ。
    public func register(_ target: FocusTarget, rect: Rect) {
        guard isCollecting else { return }
        // 追加するだけにしたくなるが、同じ対象が 2 度並ぶと Tab が同じウィジェットを 2 回巡る。
        if let index = pending.firstIndex(where: { $0.target === target }) {
            pending[index].rect = rect
            return
        }
        pending.append(Entry(target: target, rect: rect))
    }

    /// 描画の始まりを知らせ、登録を受け付ける状態にする。
    func beginFrame() {
        isCollecting = true
        pending = []
    }

    /// 描画の終わりを知らせ、この描画の登録を確定する。
    ///
    /// - Postcondition: 描画されなかった対象はフォーカスを失う。
    ///   `focusesFirstAutomatically` が有効なら、フォーカスは最初の対象へ移る。
    func endFrame() {
        isCollecting = false
        entries = pending
        pending = []

        if let current = focusedTarget, index(of: current) == nil {
            focusedTarget = nil
        }
        if focusedTarget == nil, focusesFirstAutomatically {
            focusedTarget = entries.first?.target
        }
    }

    /// キーがフォーカスの移動なら、移動した結果を返す。
    ///
    /// - Parameters:
    ///   - event: 押されたキー。
    /// - Returns: 移動なら移した結果、そうでなければ `nil`。
    private func moveFocus(for event: KeyEvent) -> Bool? {
        switch event.key {
        case .tab:
            return focusNext()
        case .backTab:
            return focusPrevious()
        default:
            return nil
        }
    }

    /// フォーカスを描画順で前後へ動かす。
    ///
    /// - Parameters:
    ///   - offset: 動かす数。正で後ろ、負で前。
    /// - Returns: 動かしたら `true`。
    private func move(by offset: Int) -> Bool {
        guard !entries.isEmpty else { return false }
        guard let current = focusedTarget, let position = index(of: current) else {
            focusedTarget = (offset > 0 ? entries.first : entries.last)?.target
            return true
        }

        let next = position + offset
        if next < 0 || next >= entries.count {
            guard wrapsAround else { return false }
            focusedTarget = entries[(next + entries.count) % entries.count].target
            return true
        }
        focusedTarget = entries[next].target
        return true
    }

    /// マウスイベントを、その位置にあるウィジェットへ配送する。
    ///
    /// - Parameters:
    ///   - mouseEvent: 配送するマウスイベント。
    /// - Returns: 配送先が処理したら `true`。
    private func deliver(_ mouseEvent: MouseEvent) -> Bool {
        // `first(where:)` にしたくなるが、後から描いたものが手前に重なるので、
        // 下に隠れたウィジェットがクリックを横取りする。
        guard let entry = entries.last(where: { $0.rect.contains(mouseEvent.position) }) else {
            return false
        }
        // どのマウスイベントでも移したくなるが、ホイールやドラッグまで含めると、
        // リストを覗いただけで入力欄からフォーカスが外れる。
        if mouseEvent.action == .press {
            focusedTarget = entry.target
        }
        return entry.target.handle(.mouse(mouseEvent))
    }

    /// 対象が登録されている位置。
    ///
    /// - Parameters:
    ///   - target: 探す対象。
    /// - Returns: 描画順の位置。登録されていなければ `nil`。
    private func index(of target: FocusTarget) -> Int? {
        entries.firstIndex { $0.target === target }
    }
}
