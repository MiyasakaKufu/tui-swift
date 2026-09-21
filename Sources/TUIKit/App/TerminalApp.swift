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
/// - Note: `main.swift` という名前のファイルでは `@main` を使えないため、
///   ファイル名は型名に合わせる（`Counter.swift` など）。
@TUIActor
public protocol TerminalApp: Component {
    /// 起動時に呼ばれる、引数のないイニシャライザ。
    init()

    /// 起動時の設定。
    static var options: ApplicationOptions { get }
}

extension TerminalApp {
    /// すべて既定値の設定。
    public static var options: ApplicationOptions { .default }

    /// アプリケーションを起動する。
    ///
    /// - Note: 端末を初期化できなかった場合は、標準エラー出力へ理由を書き、
    ///   終了コード 1 で抜ける。
    // @main は隔離の付いた main() を受け付けない（型が () async -> Void に合わない）。
    // nonisolated にして、中でアクタへ入り直す。
    nonisolated public static func main() async {
        do {
            try await Application<Self>.start()
        } catch {
            fputs("起動できませんでした: \(error)\n", stderr)
            exit(1)
        }
    }
}
