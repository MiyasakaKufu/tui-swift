#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `@main` を付けるだけで起動できるアプリケーション。
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
/// `main.swift` という名前のファイルでは `@main` を使えないため、
/// ファイル名は型名に合わせる（`Counter.swift` など）。
public protocol TerminalApp: Component {
    init()

    /// 起動時の設定。
    static var options: ApplicationOptions { get }
}

extension TerminalApp {
    public static var options: ApplicationOptions { .default }

    public static func main() {
        do {
            try Application(root: Self(), options: options).run()
        } catch {
            fputs("起動できませんでした: \(error)\n", stderr)
            exit(1)
        }
    }
}
