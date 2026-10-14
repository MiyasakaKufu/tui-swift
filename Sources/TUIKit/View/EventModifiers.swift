/// ``KeyPressView/content`` の内側がフォーカスを持つ間、``KeyPressView/key`` を受け取る ``View``。``View/onKeyPress(_:action:)`` で作る。
public struct KeyPressView<Content: View>: View {
    /// ``KeyPressView/key`` を受け取る範囲の ``View``。
    public var content: Content
    /// 受け取る ``Key``。
    public var key: Key
    /// ``KeyPressView/key`` を受け取ったときに呼び出すクロージャ。
    let action: @MainActor () -> EventResult

    /// ``KeyPressView`` を作る。
    ///
    /// - Parameters:
    ///   - content: `key` を受け取る範囲の ``View``。
    ///   - key: 受け取る ``Key``。
    ///   - action: `key` を受け取ったときに呼び出すクロージャ。
    init(content: Content, key: Key, action: @escaping @MainActor () -> EventResult) {
        self.content = content
        self.key = key
        self.action = action
    }

    /// ``KeyPressView/key`` を受け取る範囲の ``KeyPressView/content``。
    public var body: Content { content }
}

/// ``View/onKeyPress(_:action:)`` で作った ``View`` が、たどったときに `FocusController` へ示すもの。
@MainActor
protocol KeyPressHandlingView {
    /// 受け取る ``Key``。
    var handledKey: Key { get }
    /// 受け取ったときに呼び出すクロージャ。
    var keyAction: @MainActor () -> EventResult { get }
}

extension KeyPressView: KeyPressHandlingView {
    /// 受け取る ``Key``。
    var handledKey: Key { key }
    /// 受け取ったときに呼び出すクロージャ。
    var keyAction: @MainActor () -> EventResult { action }
}

/// ``ChangeObservingView/value`` の変化を見つけてクロージャを呼び出す ``View``。``View/onChange(of:_:)`` で作る。
public struct ChangeObservingView<Content: View, Value: Equatable>: View {
    /// ``ChangeObservingView/value`` を見張る間に描く ``View``。
    public var content: Content
    /// 見張る値。
    public var value: Value
    /// 変化を見つけたときに、変化の前の値と後の値を受け取るクロージャ。
    let action: @MainActor (Value, Value) -> Void

    /// ``ChangeObservingView`` を作る。
    ///
    /// - Parameters:
    ///   - content: `value` を見張る間に描く ``View``。
    ///   - value: 見張る値。
    ///   - action: 変化を見つけたときに、変化の前の値と後の値を受け取るクロージャ。
    init(content: Content, value: Value, action: @escaping @MainActor (Value, Value) -> Void) {
        self.content = content
        self.value = value
        self.action = action
    }

    /// ``ChangeObservingView/value`` を見張る間に描く ``ChangeObservingView/content``。
    public var body: Content { content }
}

/// ``View/onChange(of:_:)`` で作った ``View`` が、たどったときに `FocusController` へ示すもの。
@MainActor
protocol ChangeObservingViewProtocol {
    /// 前に `node` でたどったときの値と比べ、変わっていれば呼び出すクロージャを返す。
    ///
    /// - Parameters:
    ///   - node: この ``View`` の `ViewNode`。
    /// - Returns: 値が変わっていれば、変化の前の値と後の値を渡してクロージャを呼び出すクロージャ。変わっていないか、初めてたどったなら `nil`。
    func detectChange(in node: ViewNode) -> (@MainActor () -> Void)?
}

extension ChangeObservingView: ChangeObservingViewProtocol {
    /// 前に `node` でたどったときの値と比べ、変わっていれば呼び出すクロージャを返す。
    ///
    /// - Parameters:
    ///   - node: この ``View`` の `ViewNode`。
    /// - Returns: 値が変わっていれば、変化の前の値と後の値を渡してクロージャを呼び出すクロージャ。変わっていないか、初めてたどったなら `nil`。
    func detectChange(in node: ViewNode) -> (@MainActor () -> Void)? {
        let record = node.object(for: changeRecordLabel) { ChangeRecord<Value>() }
        let previous = record.value
        record.value = value
        guard let previous, previous != value else { return nil }
        let action = self.action
        let current = value
        return { action(previous, current) }
    }
}

// Swift の識別子に使える名前へ変えたくなるが、`View.onChange(of:_:)` を付けた `View` が同じ名前のプロパティに `@State` を付けていると、`ViewNode` の同じ記憶域を取り合い、どちらかの値が失われる。
/// ``ChangeObservingView`` が `ViewNode` に置く記憶域の名前。
private let changeRecordLabel = "onChange(of:)"

/// ``ChangeObservingView`` が前にたどったときの値を持つ記憶域。
@MainActor
final class ChangeRecord<Value> {
    /// 前にたどったときの値。まだたどっていなければ `nil`。
    var value: Value?
}

extension View {
    /// この ``View`` の内側がフォーカスを持つ間に `key` が押されたら、`action` を呼び出す。
    ///
    /// フォーカスを持つ ``View``（``TextField``・``ListView``）が処理しなかった `key` を受け取る。この ``View`` の内側に ``View/onKeyPress(_:action:)`` があれば、内側のものから先に受け取る。
    ///
    /// - Parameters:
    ///   - key: 受け取る ``Key``。
    ///   - action: `key` が押されたときに呼び出すクロージャ。処理したら `.handled`、しなければ `.ignored` を返す。``Application`` を終了するには、``TerminalApp/isFinished`` を `true` にする。
    /// - Returns: `action` を登録した ``KeyPressView``。
    /// - Note: 修飾キーの付いた押下では `action` を呼び出さない。文字のキーだけは、Shift だけが付いた押下でも呼び出す。
    /// - Note: `action` の中では、``State``・``FocusState`` を付けたプロパティへ代入してよい。
    public func onKeyPress(
        _ key: Key,
        action: @escaping @MainActor () -> EventResult
    ) -> KeyPressView<Self> {
        KeyPressView(content: self, key: key, action: action)
    }

    /// `value` が前の `Application.draw()` の 1 回から変わったら、その `Application.draw()` の 1 回が終わった後に `action` を呼び出す。
    ///
    /// - Parameters:
    ///   - value: 見張る値。
    ///   - action: `value` が変わったときに呼び出すクロージャ。
    /// - Returns: `value` を見張る ``ChangeObservingView``。
    /// - Note: 比べるのは、描画より前にたどったときの値どうし。`action` を呼び出した後、`Application.draw()` をもう 1 回行う。そのもう 1 回で値がまた変わっても、`action` は呼び出すが、さらには描き直さない。
    /// - Note: `action` の中では、``State``・``FocusState`` を付けたプロパティへ代入してよい。
    public func onChange<Value: Equatable>(
        of value: Value,
        _ action: @escaping @MainActor () -> Void
    ) -> ChangeObservingView<Self, Value> {
        ChangeObservingView(content: self, value: value) { _, _ in action() }
    }

    /// `value` が前の `Application.draw()` の 1 回から変わったら、その `Application.draw()` の 1 回が終わった後に、変化の前の値と後の値を渡して `action` を呼び出す。
    ///
    /// - Parameters:
    ///   - value: 見張る値。
    ///   - action: `value` が変わったときに、変化の前の値と後の値を受け取るクロージャ。
    /// - Returns: `value` を見張る ``ChangeObservingView``。
    /// - Note: 比べるのは、描画より前にたどったときの値どうし。`action` を呼び出した後、`Application.draw()` をもう 1 回行う。そのもう 1 回で値がまた変わっても、`action` は呼び出すが、さらには描き直さない。
    /// - Note: `action` の中では、``State``・``FocusState`` を付けたプロパティへ代入してよい。
    public func onChange<Value: Equatable>(
        of value: Value,
        _ action: @escaping @MainActor (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> ChangeObservingView<Self, Value> {
        ChangeObservingView(content: self, value: value, action: action)
    }
}
