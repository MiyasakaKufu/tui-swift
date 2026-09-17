/// レンダラの出力先。
public protocol TerminalOutput: AnyObject {
    /// 文字列を出力バッファへ追加する。
    func write(_ text: String)
    /// 溜めた出力を実際に書き出す。
    func flush()
}

/// テスト用に出力を文字列として溜め込む出力先。
public final class StringOutput: TerminalOutput {
    public private(set) var contents: String = ""
    public private(set) var flushCount: Int = 0

    public init() {}

    public func write(_ text: String) {
        contents += text
    }

    public func flush() {
        flushCount += 1
    }

    public func reset() {
        contents = ""
        flushCount = 0
    }
}
