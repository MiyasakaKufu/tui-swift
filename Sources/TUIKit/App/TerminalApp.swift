import CTUIShim

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ``TerminalApp/handle(_:)`` と ``TerminalApp/receive(_:)`` が返す、処理したかどうかを表す型。
public enum EventResult: Hashable, Sendable {
    /// 処理した。
    case handled
    /// 処理しなかった。
    case ignored
}

/// ``Application`` に ``View`` を返し、``InputEvent`` と ``TerminalApp/Message`` を受け取り、`@main` を付けるだけで ``Application`` を起動できる型が準拠するプロトコル。
///
///     @main
///     final class Counter: TerminalApp {
///         private var count = 0
///
///         var body: some View {
///             Text("カウント: \(count)")
///         }
///     }
///
/// `@main` を別の型に付けている場合（CLI のコマンドを定義するライブラリを使う場合など）は、その型のメソッドから ``TerminalApp/run()-swift.method`` か ``TerminalApp/run()-swift.type.method`` を呼び出して起動する。
///
///     func run() async throws {
///         try await Viewer(path: path).run()
///     }
///
/// - Note: `main.swift` という名前のファイルでは `@main` を使えないため、
///   ファイル名は型名に合わせる（`Counter.swift` など）。
/// - Note: `static func main()` を持つ別のプロトコルに同じ型を準拠させると、`@main` がどちらの `main()` を呼び出すか決まらず、コンパイルできない。
///   `@main` を付ける型と ``TerminalApp`` に準拠する型を分ける。
@MainActor
public protocol TerminalApp: AnyObject {
    /// ``TerminalApp/body`` が返す ``View`` の型。準拠する型が ``TerminalApp/body`` を `some View` で書けば推論される。
    associatedtype Body: View

    /// `MessageSender.send(_:)` で送る値の型。`receive(_:)` を書けば推論される。
    ///
    /// 既定は `Never`。`MessageSender` を使わないなら決めなくてよい。
    associatedtype Message: Sendable = Never

    /// ``TerminalApp/run()-swift.type.method`` と ``TerminalApp/main()`` が起動する、``TerminalApp`` に準拠する型のインスタンスを作る。
    init()

    /// 起動時の設定。
    static var options: ApplicationOptions { get }

    /// 現在の状態から画面を組み立てる。
    var body: Body { get }

    /// 入力イベントを処理する。
    ///
    /// - Parameters:
    ///   - event: ``Application`` が渡す ``InputEvent``。
    /// - Returns: 処理したかどうかを表す ``EventResult``。
    /// - Note: 受け取るのは、フォーカスを持つ ``View``（``TextField``・``ListView``）、``View/onKeyPress(_:action:)`` のクロージャ、Tab・Shift+Tab によるフォーカスの移動、クリックした位置の ``View`` のどれも処理しなかった ``InputEvent`` だけ。Tab・Shift+Tab を受け取るのは、フォーカスを受け取る ``View`` が 1 つも無いときだけ。
    func handle(_ event: InputEvent) -> EventResult

    /// 別スレッドや `Task` から `MessageSender.send(_:)` で送られた値を処理する。
    ///
    /// - Parameters:
    ///   - message: 送られた値。
    /// - Returns: 処理したかどうかを表す ``EventResult``。
    /// - Note: 送られた順に呼び出される。``TerminalApp/handle(_:)`` との前後は、``InputReader`` が端末デバイスからキーのバイト列を読んだ時点で決まる。キーが端末デバイスに届いた時点ではないので、届いてから読むまでの間に送られた値は、そのキーより先に渡る。
    func receive(_ message: Message) -> EventResult

    /// 端末エミュレータのカーソルを表示したい位置。
    ///
    /// - Note: `nil` なら、フォーカスを持つ ``TextField`` が示す位置に置く。その ``TextField`` が無いか、描画されなかったなら隠す。
    var cursorPosition: Point? { get }

    /// ``Application`` を終了するかどうか。
    ///
    /// - Note: ``Application`` は、``TerminalApp/handle(_:)``・``TerminalApp/receive(_:)``・``View/onKeyPress(_:action:)`` のクロージャ・``TerminalApp/update(elapsed:)`` を呼び出すたびに読み、`true` ならイベントループを抜ける。同じ時点に届いていた残りの ``InputEvent`` は渡さない。
    /// - Note: ``View/onKeyPress(_:action:)`` のクロージャから終了するには、このプロパティを書き換える ``Binding`` を ``View`` へ渡す。
    var isFinished: Bool { get }

    /// `Application.draw()` の直前に、前に呼び出されてからの経過秒数を受け取る。
    ///
    /// - Parameters:
    ///   - elapsed: 前に ``TerminalApp/update(elapsed:)`` を呼び出してからの経過秒数。
    ///     初回は ``Application/run()`` が最初の `.resize` を通知した時点から測り、一時停止していた時間は含めない。
    /// - Note: ``InputEvent``・``TerminalApp/Message`` を処理するたびに呼び出され、``ApplicationOptions/frameInterval`` を設定したときは、入力が無くてもその間隔で呼び出される。最初の `Application.draw()` の前には呼び出されない。
    func update(elapsed: Double)

    /// イベントループが回っている間、非同期の処理を実行する。
    ///
    /// ``Application`` は、最初の `Application.draw()` の 1 回の後にこのメソッドを `Task` の中で呼び出し、イベントループを抜けると、その `Task` を打ち切る。
    /// 画面に出すものは `sender` で送り、``TerminalApp/receive(_:)`` で受け取る。
    ///
    ///     func task(sender: MessageSender<Message>) async {
    ///         for await line in lines {
    ///             sender.send(.received(line))
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - sender: ``TerminalApp/Message`` の値をイベントループへ送る ``MessageSender``。別の `Task` や別スレッドへ渡してよい。
    /// - Note: プロパティへ代入しただけでは描き直さない。次に ``InputEvent`` か ``TerminalApp/Message`` が届くまで、画面に出ない。
    /// - Note: 最初の `.resize` で ``TerminalApp/isFinished`` が `true` になったときは、呼び出さない。
    /// - Note: 打ち切られた後に送った値は届かない（``MessageSender/send(_:)`` が `false` を返す）。
    /// - Warning: ``Application/run()`` は、この `Task` が終わるのを待ってから戻る。打ち切りに応じない処理（`Task.isCancelled` を見ずに回り続けるループなど）を書くと、端末デバイスの termios を戻した後も ``Application/run()`` が戻らず、プロセスが終わらない。
    func task(sender: MessageSender<Message>) async

    /// 一時停止する直前に、一時停止することを受け取る。
    ///
    /// 端末デバイスの termios と、端末エミュレータへ送ったモードを戻した後に呼び出される。
    ///
    /// - Note: 一時停止したまま SIGKILL などで終わらされると、``TerminalApp/didTerminate(_:)`` は呼び出されない。失いたくない値は、ここで書き出す。
    /// - Note: 捕まえられない SIGSTOP で止められたときは呼び出されない。再開したときの ``TerminalApp/didResume()`` だけが呼び出される。
    func willSuspend()

    /// 一時停止から再開したことを受け取る。
    ///
    /// 端末デバイスを raw モードへ戻した後、描き直す前に呼び出される。
    ///
    /// - Note: 端末デバイスを raw モードへ戻せなかったときは呼び出さず、イベントループを抜けて ``TerminalApp/didTerminate(_:)`` に `.resumeFailed` を渡す。
    func didResume()

    /// イベントループを抜けたことを、その理由とともに受け取る。
    ///
    /// 端末デバイスの termios と、端末エミュレータへ送ったモードを戻し、``TerminalApp/task(sender:)`` が終わった後に呼び出される。``Application`` が呼び出す、このインスタンスのメソッドのうち最後のもの。標準出力へ書き出したものは、シェルの画面に残る。
    ///
    /// - Parameters:
    ///   - reason: イベントループを抜けた理由。
    /// - Note: ``Application/run()`` がイベントループを回す前にエラーを投げたときは呼び出されない。
    func didTerminate(_ reason: TerminationReason)
}

extension TerminalApp {
    /// すべて既定値の設定。
    public static var options: ApplicationOptions { .default }

    /// 表示専用の ``TerminalApp`` に準拠する型は入力を扱わなくてよい。
    ///
    /// - Parameters:
    ///   - event: ``Application`` が渡す ``InputEvent``。
    /// - Returns: 常に `.ignored`。
    /// - Note: すべてのイベントが未処理になるが、`ApplicationOptions.quitsOnControlC`
    ///   が既定で有効なため Ctrl+C で終了できる。
    public func handle(_ event: InputEvent) -> EventResult { .ignored }

    /// ``MessageSender`` を使わない ``TerminalApp`` に準拠する型は、``TerminalApp/Message`` を受け取らなくてよい。
    ///
    /// - Parameters:
    ///   - message: 送られた値。
    /// - Returns: 常に `.ignored`。
    public func receive(_ message: Message) -> EventResult { .ignored }

    /// `nil`。フォーカスを持つ ``TextField`` が示す位置にカーソルを置く。
    public var cursorPosition: Point? { nil }

    /// `false`。Ctrl+C（``ApplicationOptions/quitsOnControlC``）か終了シグナルで終了する。
    public var isFinished: Bool { false }

    /// 何もしない。
    ///
    /// - Parameters:
    ///   - elapsed: 前に ``TerminalApp/update(elapsed:)`` を呼び出してからの経過秒数。
    ///     初回は ``Application/run()`` が最初の `.resize` を通知した時点から測り、一時停止していた時間は含めない。
    public func update(elapsed: Double) {}

    /// 何もしない。
    ///
    /// - Parameters:
    ///   - sender: ``TerminalApp/Message`` の値をイベントループへ送る ``MessageSender``。
    public func task(sender: MessageSender<Message>) async {}

    /// 何もしない。
    public func willSuspend() {}

    /// 何もしない。
    public func didResume() {}

    /// 何もしない。
    ///
    /// - Parameters:
    ///   - reason: イベントループを抜けた理由。
    public func didTerminate(_ reason: TerminationReason) {}

    /// 引数のないイニシャライザで作ったインスタンスと ``TerminalApp/options`` で ``Application`` を起動し、終了するまでイベントループを回す。
    ///
    /// - Throws: ``Application/run()`` が投げるもの。
    public static func run() async throws {
        try await Self().run()
    }

    /// このインスタンスと ``TerminalApp/options`` で ``Application`` を起動し、終了するまでイベントループを回す。
    ///
    /// - Throws: ``Application/run()`` が投げるもの。
    public func run() async throws {
        try await Application(root: self, options: Self.options).run()
    }

    /// `@main` を付けた型のエントリポイントとして、引数のないイニシャライザで作ったインスタンスと ``TerminalApp/options`` で ``Application`` を起動し、終了するまでイベントループを回す。
    ///
    /// - Note: ``Application/run()`` がエラーを投げた場合は、標準エラー出力へ理由を書き、終了コード 1 で抜ける。
    public static func main() async {
        do {
            try await Self.run()
        } catch {
            ctui_write_standard_error("起動できませんでした: \(error)\n")
            exit(1)
        }
    }
}
