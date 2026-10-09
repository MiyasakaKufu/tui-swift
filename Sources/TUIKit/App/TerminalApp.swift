import CTUIShim

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `@main` を付けるだけで `Application` を起動できる型が準拠するプロトコル。
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
/// - Note: `main.swift` という名前のファイルでは `@main` を使えないため、
///   ファイル名は型名に合わせる（`Counter.swift` など）。
@MainActor
public protocol TerminalApp: Component {
    /// 起動時に呼び出される、引数のないイニシャライザ。
    init()

    /// 起動時の設定。
    static var options: ApplicationOptions { get }
}

extension TerminalApp {
    /// イニシャライザの引数をすべて省いて作った `ApplicationOptions`（`ApplicationOptions.default`）。
    public static var options: ApplicationOptions { .default }

    /// `Application` を作って起動する。
    ///
    /// - Note: `Application.run()` がエラーを投げた場合は、標準エラー出力へ理由を書き、
    ///   終了コード 1 で抜ける。
    public static func main() async {
        do {
            try await Application<Self>.start()
        } catch {
            ctui_write_standard_error("起動できませんでした: \(error)\n")
            exit(1)
        }
    }
}
