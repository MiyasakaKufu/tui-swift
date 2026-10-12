/// ``Application`` が持ち、`ViewGraph` と `FocusController` をまとめるクラス。
///
/// `ViewGraph` がたどった ``View`` の一覧を `FocusController` へ渡し、`FocusController` が描画より前にフォーカスを決める。`ViewGraph` はフォーカスを知らず、`ViewGraph.environment` で `FocusController` を ``View`` へ渡すだけ。
@MainActor
final class ApplicationContext {
    /// `ViewNode` を `ViewPath` ごとに保持する `ViewGraph`。
    let graph = ViewGraph()

    /// フォーカスを保持する `FocusController`。
    let focus = FocusController()

    /// `ApplicationContext` を作る。
    init() {
        graph.environment.focus = focus
    }

    /// フォーカスを持つ ``TextField`` が直前の描画で示した、端末エミュレータのカーソルの位置。描画されなかったか、フォーカスを持つ ``TextField`` が無ければ `nil`。
    var cursorPosition: Point? {
        focus.cursorPosition(in: graph.cursorPoints)
    }

    /// `makeView` が返す ``View`` を `ViewPath.root` に置いて `Application.draw()` の 1 回分を描き、`present` に渡す。
    ///
    /// - Parameters:
    ///   - makeView: ``Application`` が最初にメソッドを呼び出す ``View`` を返すクロージャ。描くたびに呼び出す。
    ///   - buffer: 描画先の ``Buffer``。画面全体として扱い、描く前に空にする。
    ///   - ambiguousWidth: ``Cell`` の数を数えるときに使う ``DisplayWidth/AmbiguousWidth``。
    ///   - present: 描き終えた ``Buffer`` を受け取るクロージャ。
    /// - Postcondition: たどった後にフォーカスが変わったか、``View/onChange(of:_:)`` が値の変化を見つけたら、もう 1 回描いて `present` に渡している。そのもう 1 回では、さらには描かない。
    func draw<V: View>(
        _ makeView: () -> V,
        into buffer: inout Buffer,
        ambiguousWidth: DisplayWidth.AmbiguousWidth,
        present: (Buffer) -> Void
    ) {
        var allowsFollowUp = true
        while true {
            buffer.clear()
            var changeActions: [@MainActor () -> Void] = []
            var focusChanged = false
            graph.renderFrame(makeView(), into: &buffer, ambiguousWidth: ambiguousWidth) { visited in
                changeActions = visited.compactMap { visitedView in
                    (visitedView.view as? any ChangeObservingViewProtocol)?.detectChange(in: visitedView.node)
                }
                focusChanged = focus.decideFocus(visiting: visited)
            }
            for action in changeActions { action() }
            present(buffer)
            guard allowsFollowUp, focusChanged || !changeActions.isEmpty else { return }
            allowsFollowUp = false
        }
    }

    /// `event` を `FocusController.deliver(_:)` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す `KeyEvent`。
    /// - Returns: `FocusController.deliver(_:)` の戻り値。
    func deliver(_ event: KeyEvent) -> EventResult? {
        focus.deliver(event)
    }

    /// `.paste` を `FocusController.deliverPaste(_:)` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す `.paste`。
    /// - Returns: `FocusController.deliverPaste(_:)` の戻り値。
    func deliverPaste(_ event: InputEvent) -> Bool {
        focus.deliverPaste(event)
    }

    /// `event` を、直前の描画で ``Buffer`` へ書き込んだ ``View`` の矩形とともに `FocusController.deliver(_:hitRegions:)` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す `MouseEvent`。
    /// - Returns: `FocusController.deliver(_:hitRegions:)` の戻り値。
    func deliver(_ event: MouseEvent) -> Bool {
        focus.deliver(event, hitRegions: graph.hitRegions)
    }
}

/// フォーカスを保持し、``InputEvent`` を ``View`` へ渡すクラス。
///
/// フォーカスは、描画より前にたどった ``View`` の一覧だけから決める。`ViewGraph` は知らない。
@MainActor
final class FocusController: FocusProviding {
    /// フォーカスを持つ ``View`` の `ViewNode.id`。どの ``View`` もフォーカスを持たなければ `nil`。
    private(set) var focusedNodeID: Int?

    /// `@FocusState` を付けたプロパティへの `nil`（`Bool` なら `false`）の代入でフォーカスを外した後なら `true`。
    private var isFocusRemovedByAssignment = false

    /// 移す先が一覧に無かったために保留している、`@FocusState` を付けたプロパティへの代入。
    private var pendingAssignment: FocusAssignment?

    /// ``View/sheet(isPresented:content:)`` の `content:` を表示する直前のフォーカスの状態。`content:` を表示している ``SheetView`` の `ViewNode.id` ごとに持つ。
    private var savedFocusBeforeSheets: [Int: SavedFocus] = [:]

    /// 直前にたどった ``View`` の一覧から作った `FocusIndex`。
    private(set) var index = FocusIndex()

    /// `FocusController` を作る。
    init() {}

    /// たどった ``View`` の一覧から `FocusController.index` を作り直し、フォーカスを決める。
    ///
    /// - Parameters:
    ///   - visited: 描画より前にたどった順に並べた `VisitedView`。
    /// - Returns: フォーカスを持つ ``View`` が変わったら `true`。
    func decideFocus(visiting visited: [ViewGraph.VisitedView]) -> Bool {
        let previousIndex = index
        index = FocusIndex(visited)

        let previousFocus = focusedNodeID

        let closedSheets = previousIndex.presentedSheets.subtracting(index.presentedSheets)
        let openedSheets = index.presentedSheets.subtracting(previousIndex.presentedSheets)
        for sheet in closedSheets.sorted() {
            guard let saved = savedFocusBeforeSheets.removeValue(forKey: sheet) else { continue }
            restore(saved)
        }
        for sheet in openedSheets.sorted() {
            savedFocusBeforeSheets[sheet] = SavedFocus(
                focusedNodeID: focusedNodeID,
                isFocusRemovedByAssignment: isFocusRemovedByAssignment
            )
            focusedNodeID = index.firstEnabledTarget?.nodeID
            isFocusRemovedByAssignment = false
        }

        if let assignment = pendingAssignment {
            pendingAssignment = nil
            if let target = index.target(for: assignment) {
                focus(target.nodeID)
            }
        }

        if let focused = focusedNodeID, !index.isEnabledTarget(focused) {
            focusedNodeID = index.firstEnabledTarget?.nodeID
        }

        if focusedNodeID == nil, !isFocusRemovedByAssignment {
            focusedNodeID = index.firstEnabledTarget?.nodeID
        }

        return focusedNodeID != previousFocus
    }

    /// ``View/sheet(isPresented:content:)`` の `content:` を表示する直前の状態へ戻す。
    ///
    /// - Parameters:
    ///   - saved: 戻す状態。
    private func restore(_ saved: SavedFocus) {
        isFocusRemovedByAssignment = saved.isFocusRemovedByAssignment
        guard let savedNodeID = saved.focusedNodeID else {
            focusedNodeID = nil
            return
        }
        focusedNodeID = index.isEnabledTarget(savedNodeID) ? savedNodeID : index.firstEnabledTarget?.nodeID
    }

    /// フォーカスを `nodeID` の ``View`` へ移す。
    ///
    /// - Parameters:
    ///   - nodeID: フォーカスを移す先の `ViewNode.id`。
    private func focus(_ nodeID: Int) {
        focusedNodeID = nodeID
        isFocusRemovedByAssignment = false
    }

    // MARK: - FocusProviding

    /// `node` の ``View`` がフォーカスを持つかを返す。
    ///
    /// - Parameters:
    ///   - node: 調べる ``View`` の `ViewNode`。
    /// - Returns: フォーカスを持てば `true`。
    func isFocused(_ node: ViewNode) -> Bool {
        focusedNodeID == node.id
    }

    /// フォーカスを持つ ``TextField`` が示した、端末エミュレータのカーソルの位置を返す。
    ///
    /// - Parameters:
    ///   - cursorPoints: 直前の描画で、描画された ``TextField`` が示した位置。`ViewNode.id` ごとに持つ。
    /// - Returns: フォーカスを持つ ``TextField`` の位置。描画されなかったか、フォーカスを持つ ``TextField`` が無ければ `nil`。
    func cursorPosition(in cursorPoints: [Int: Point]) -> Point? {
        guard let focusedNodeID else { return nil }
        return cursorPoints[focusedNodeID]
    }

    /// `storage` に結び付いた ``View`` のうち、フォーカスを持つものの値を返す。
    ///
    /// - Parameters:
    ///   - storage: `@FocusState` を付けたプロパティの記憶域。
    /// - Returns: フォーカスを持つ ``View`` に `storage` が結び付いていれば、その ``View/focused(_:equals:)`` の `equals:` 引数の値（``View/focused(_:)`` なら `true`）。結び付いていなければ `nil`。
    func focusedValue(of storage: any AnyFocusStateStorage) -> AnyHashable? {
        guard let focusedNodeID else { return nil }
        return index.bindings
            .first { $0.storage === storage && index.binding($0, matches: focusedNodeID) }?
            .value
    }

    /// `@FocusState` を付けたプロパティへの代入を、フォーカスへ反映する。
    ///
    /// - Parameters:
    ///   - value: 代入された値。`nil`（`Bool` なら `false`）が代入されたなら `nil`。
    ///   - storage: 代入された `@FocusState` を付けたプロパティの記憶域。
    /// - Postcondition: 移す先が直前にたどった一覧に無ければ、代入を保留し、次の `Application.draw()` の 1 回で、描画より前に 1 回だけ試みる。それより前に保留していた代入は捨てる。
    func assign(_ value: AnyHashable?, to storage: any AnyFocusStateStorage) {
        pendingAssignment = nil
        guard let value else {
            if focusedValue(of: storage) != nil {
                focusedNodeID = nil
                isFocusRemovedByAssignment = true
            }
            return
        }

        let assignment = FocusAssignment(storage: storage, value: value)
        if let target = index.target(for: assignment) {
            focus(target.nodeID)
        } else {
            pendingAssignment = assignment
        }
    }

    // MARK: - InputEvent を渡す

    /// `event` を、フォーカスを持つ ``View``、それを内側に含む ``View`` の ``View/onKeyPress(_:action:)`` のクロージャ、Tab・Shift+Tab によるフォーカスの移動の順に渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す `KeyEvent`。
    /// - Returns: どれかが処理したら `.handled`、``View/onKeyPress(_:action:)`` のクロージャが `.quit` を返したら `.quit`。どれも処理しなければ `nil`。
    func deliver(_ event: KeyEvent) -> EventResult? {
        if let target = focusedTarget {
            if target.handle(.key(event)) { return .handled }

            let handlers = index.keyPressHandlers
                .filter { !$0.isBehindSheet && $0.path.contains(target.path) && $0.accepts(event) }
                .sorted { $0.path.depth > $1.path.depth }
            for handler in handlers {
                let result = handler.action()
                if result != .ignored { return result }
            }
        }

        if event.modifiers.isEmpty, event.key == .tab || event.key == .backTab {
            if moveFocus(forward: event.key == .tab) { return .handled }
        }
        return nil
    }

    /// `.paste` を、フォーカスを持つ ``View`` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す `.paste`。
    /// - Returns: フォーカスを持つ ``View`` が処理したら `true`。
    func deliverPaste(_ event: InputEvent) -> Bool {
        focusedTarget?.handle(event) ?? false
    }

    /// `event` を、その位置でいちばん手前に ``Buffer`` へ書き込んだ ``View`` か、それを内側に含む ``View`` のうち、最も内側にあるフォーカスを受け取る ``View`` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す `MouseEvent`。
    ///   - hitRegions: 直前の描画で ``View`` が ``Buffer`` へ書き込んだ矩形。書き込んだ順に並ぶ。
    /// - Returns: 渡した ``View`` が処理したら `true`。渡す先が無ければ `false`。
    /// - Postcondition: `event` がボタンの押下で、渡す先があれば、渡す前にフォーカスをそこへ移している。
    func deliver(_ event: MouseEvent, hitRegions: [HitRegion]) -> Bool {
        guard let region = hitRegions.last(where: { $0.rect.contains(event.position) }),
              !index.isBehindSheet(region.path),
              let target = index.targets
                .filter({ !$0.isBehindSheet && $0.path.contains(region.path) })
                .max(by: { $0.path.depth < $1.path.depth })
        else { return false }

        if event.action == .press {
            pendingAssignment = nil
            focus(target.nodeID)
        }
        return target.handle(.mouse(event))
    }

    /// フォーカスを持ち、``View/sheet(isPresented:content:)`` の `content:` の後ろに無い ``View`` の `FocusTarget`。
    private var focusedTarget: FocusTarget? {
        guard let focusedNodeID else { return nil }
        return index.targets.first { $0.nodeID == focusedNodeID && !$0.isBehindSheet }
    }

    /// フォーカスを受け取る ``View`` の間で、たどった順にフォーカスを移す。
    ///
    /// - Parameters:
    ///   - forward: たどった順の後ろへ移すなら `true`、前へ移すなら `false`。
    /// - Returns: フォーカスを受け取る ``View`` が 1 つも無ければ `false`。
    private func moveFocus(forward: Bool) -> Bool {
        let targets = index.targets.filter { !$0.isBehindSheet }
        guard !targets.isEmpty else { return false }
        let next: Int
        if let current = targets.firstIndex(where: { $0.nodeID == focusedNodeID }) {
            next = (current + (forward ? 1 : targets.count - 1)) % targets.count
        } else {
            next = forward ? 0 : targets.count - 1
        }
        pendingAssignment = nil
        focus(targets[next].nodeID)
        return true
    }
}

/// `@FocusState` を付けたプロパティへの代入 1 回分。
@MainActor
struct FocusAssignment {
    /// 代入された `@FocusState` を付けたプロパティの記憶域。
    let storage: any AnyFocusStateStorage
    /// 代入された値。
    let value: AnyHashable
}

/// ``View/sheet(isPresented:content:)`` の `content:` を表示する直前のフォーカスの状態。
struct SavedFocus {
    /// フォーカスを持っていた ``View`` の `ViewNode.id`。
    let focusedNodeID: Int?
    /// `@FocusState` を付けたプロパティへの代入でフォーカスを外した後だったなら `true`。
    let isFocusRemovedByAssignment: Bool
}

/// たどった ``View`` の一覧のうち、フォーカスと ``InputEvent`` を渡す先を決めるのに使うもの。
@MainActor
struct FocusIndex {
    /// フォーカスを受け取る ``View``。たどった順に並ぶ。
    private(set) var targets: [FocusTarget] = []
    /// ``View/focused(_:equals:)``・``View/focused(_:)`` の結び付き。たどった順に並ぶ。
    private(set) var bindings: [FocusBinding] = []
    /// ``View/onKeyPress(_:action:)`` のクロージャ。
    private(set) var keyPressHandlers: [KeyPressHandler] = []
    /// `content:` を表示している ``SheetView`` の `ViewNode.id`。
    private(set) var presentedSheets: Set<Int> = []
    /// `content:` を表示している ``SheetView`` の後ろにある ``View`` の `ViewPath` が始まる `ViewPath`。
    private var behindSheetPaths: [ViewPath] = []

    /// 空の `FocusIndex` を作る。
    init() {}

    /// たどった ``View`` の一覧から `FocusIndex` を作る。
    ///
    /// - Parameters:
    ///   - visited: たどった順に並べた `VisitedView`。
    init(_ visited: [ViewGraph.VisitedView]) {
        for visitedView in visited {
            let view = visitedView.view
            let node = visitedView.node
            let isBehindSheet = isBehindSheet(node.path)

            if let sheet = view as? any SheetPresentingView, sheet.isPresentingSheet {
                presentedSheets.insert(node.id)
                behindSheetPaths.append(sheet.pathBehindSheet(from: node.path))
            }
            if let focusable = view as? any FocusableView {
                targets.append(FocusTarget(
                    nodeID: node.id,
                    path: node.path,
                    isBehindSheet: isBehindSheet,
                    handle: { focusable.handleFocusedEvent($0) }
                ))
            }
            if let focused = view as? any FocusBindingView, let storage = focused.focusStorage {
                bindings.append(FocusBinding(
                    path: node.path,
                    storage: storage,
                    value: focused.focusValue,
                    matchesAnyDescendant: focused.matchesAnyDescendant
                ))
            }
            if let handler = view as? any KeyPressHandlingView {
                keyPressHandlers.append(KeyPressHandler(
                    path: node.path,
                    key: handler.handledKey,
                    isBehindSheet: isBehindSheet,
                    action: handler.keyAction
                ))
            }
        }
    }

    /// ``View/sheet(isPresented:content:)`` の `content:` の後ろに無い、フォーカスを受け取る ``View`` のうち、たどった順で先頭のもの。
    var firstEnabledTarget: FocusTarget? {
        targets.first { !$0.isBehindSheet }
    }

    /// `nodeID` の ``View`` が、``View/sheet(isPresented:content:)`` の `content:` の後ろに無い、フォーカスを受け取る ``View`` かを返す。
    ///
    /// - Parameters:
    ///   - nodeID: 調べる `ViewNode.id`。
    /// - Returns: そうなら `true`。
    func isEnabledTarget(_ nodeID: Int) -> Bool {
        targets.contains { $0.nodeID == nodeID && !$0.isBehindSheet }
    }

    /// `path` の ``View`` が、``View/sheet(isPresented:content:)`` の `content:` の後ろにあるかを返す。
    ///
    /// - Parameters:
    ///   - path: 調べる ``View`` の `ViewPath`。
    /// - Returns: 後ろにあれば `true`。
    func isBehindSheet(_ path: ViewPath) -> Bool {
        behindSheetPaths.contains { $0.contains(path) }
    }

    /// `binding` が、`nodeID` の ``View`` がフォーカスを持つときに当てはまるかを返す。
    ///
    /// - Parameters:
    ///   - binding: 調べる `FocusBinding`。
    ///   - nodeID: フォーカスを持つ ``View`` の `ViewNode.id`。
    /// - Returns: `binding` が ``View/focused(_:equals:)`` のものなら、その内側で、たどった順で先頭のフォーカスを受け取る ``View`` が `nodeID` のとき `true`。``View/focused(_:)`` のものなら、内側のどれかが `nodeID` のとき `true`。
    func binding(_ binding: FocusBinding, matches nodeID: Int) -> Bool {
        if binding.matchesAnyDescendant {
            return targets.contains { $0.nodeID == nodeID && binding.path.contains($0.path) }
        }
        return targets.first { binding.path.contains($0.path) }?.nodeID == nodeID
    }

    /// `assignment` の移す先を返す。
    ///
    /// - Parameters:
    ///   - assignment: `@FocusState` を付けたプロパティへの代入。
    /// - Returns: `assignment` の値を渡した ``View/focused(_:equals:)``・``View/focused(_:)`` の内側で、たどった順で先頭の、``View/sheet(isPresented:content:)`` の `content:` の後ろに無いフォーカスを受け取る ``View``。無ければ `nil`。
    func target(for assignment: FocusAssignment) -> FocusTarget? {
        for binding in bindings where binding.storage === assignment.storage && binding.value == assignment.value {
            if let target = targets.first(where: { !$0.isBehindSheet && binding.path.contains($0.path) }) {
                return target
            }
        }
        return nil
    }
}

/// フォーカスを受け取る ``View`` 1 つ分。
@MainActor
struct FocusTarget {
    /// ``View`` の `ViewNode.id`。
    let nodeID: Int
    /// ``View`` の `ViewPath`。
    let path: ViewPath
    /// ``View/sheet(isPresented:content:)`` の `content:` の後ろにあれば `true`。
    let isBehindSheet: Bool
    /// ``InputEvent`` を受け取り、処理したら `true` を返すクロージャ。
    let handle: @MainActor (InputEvent) -> Bool
}

/// ``View/onKeyPress(_:action:)`` 1 つ分。
@MainActor
struct KeyPressHandler {
    /// ``View/onKeyPress(_:action:)`` の戻り値の ``View`` の `ViewPath`。
    let path: ViewPath
    /// ``View/onKeyPress(_:action:)`` に渡された ``Key``。
    let key: Key
    /// ``View/sheet(isPresented:content:)`` の `content:` の後ろにあれば `true`。
    let isBehindSheet: Bool
    /// ``View/onKeyPress(_:action:)`` に渡されたクロージャ。
    let action: @MainActor () -> EventResult

    /// `event` で `KeyPressHandler.action` を呼び出すかを返す。
    ///
    /// - Parameters:
    ///   - event: 調べる `KeyEvent`。
    /// - Returns: `event` の ``Key`` が `KeyPressHandler.key` と同じで、修飾キーが無ければ `true`。文字のキーは、Shift だけが付いていても `true`。
    func accepts(_ event: KeyEvent) -> Bool {
        guard event.key == key else { return false }
        if case .character = key { return event.modifiers.isEmpty || event.modifiers == .shift }
        return event.modifiers.isEmpty
    }
}

/// ``View/focused(_:equals:)``・``View/focused(_:)`` 1 つ分。
@MainActor
struct FocusBinding {
    /// ``View/focused(_:equals:)``・``View/focused(_:)`` の戻り値の ``View`` の `ViewPath`。
    let path: ViewPath
    /// 結び付いた `@FocusState` を付けたプロパティの記憶域。
    let storage: any AnyFocusStateStorage
    /// フォーカスがあるときの `@FocusState` を付けたプロパティの値。
    let value: AnyHashable
    /// ``View/focused(_:)`` のものなら `true`。内側のどの ``View`` がフォーカスを持っても当てはまる。
    let matchesAnyDescendant: Bool
}

/// フォーカスを受け取る ``View``（``TextField``・``ListView``）が、たどったときに `FocusController` へ示すもの。
@MainActor
protocol FocusableView {
    /// フォーカスを持つ間に ``InputEvent`` を受け取る。
    ///
    /// - Parameters:
    ///   - event: 受け取る ``InputEvent``。
    /// - Returns: 処理したら `true`。
    func handleFocusedEvent(_ event: InputEvent) -> Bool
}

extension TextField: FocusableView {
    /// フォーカスを持つ間に ``InputEvent`` を ``TextFieldState/handle(_:)`` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 受け取る ``InputEvent``。
    /// - Returns: ``TextFieldState/handle(_:)`` の戻り値。
    func handleFocusedEvent(_ event: InputEvent) -> Bool {
        state.handle(event)
    }
}

extension ListView: FocusableView {
    /// フォーカスを持つ間に ``InputEvent`` を ``ListState/handle(_:)`` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 受け取る ``InputEvent``。
    /// - Returns: ``ListState/handle(_:)`` の戻り値。
    func handleFocusedEvent(_ event: InputEvent) -> Bool {
        state.handle(event)
    }
}
