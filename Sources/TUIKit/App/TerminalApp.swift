import CTUIShim

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `@main` を付けるだけで ``Application`` を起動できる型が準拠するプロトコル。
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
public protocol TerminalApp: Component {
    /// ``TerminalApp/run()-swift.type.method`` と ``TerminalApp/main()`` が起動する、``TerminalApp`` に準拠する型のインスタンスを作る。
    init()

    /// 起動時の設定。
    static var options: ApplicationOptions { get }
}

extension TerminalApp {
    /// すべて既定値の設定。
    public static var options: ApplicationOptions { .default }

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
