/// レンダラの出力先。
public protocol TerminalOutput: AnyObject {
    /// 文字列を出力バッファへ追加する。
    ///
    /// - Parameters:
    ///   - text: 追加する文字列。
    func write(_ text: String)
    /// 溜めた出力を実際に書き出す。
    func flush()
}

/// テスト用に出力を文字列として溜め込む出力先。
public final class StringOutput: TerminalOutput {
    /// これまでに書き込まれた文字列。
    public private(set) var contents: String = ""
    /// `write(_:)` が呼ばれた回数。
    public private(set) var writeCount: Int = 0
    /// `flush()` が呼ばれた回数。
    public private(set) var flushCount: Int = 0

    /// 空の出力先を作る。
    public init() {}

    /// 文字列を `contents` の末尾へ足す。
    ///
    /// - Parameters:
    ///   - text: 足す文字列。
    public func write(_ text: String) {
        contents += text
        writeCount += 1
    }

    /// `flushCount` を 1 つ増やす。
    public func flush() {
        flushCount += 1
    }

    /// 書き込まれた内容と呼び出し回数を捨てる。
    public func reset() {
        contents = ""
        writeCount = 0
        flushCount = 0
    }
}
