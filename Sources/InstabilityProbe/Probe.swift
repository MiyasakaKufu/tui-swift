// H11 の計測。利用者が書きうる「別の実行文脈から UI の状態に触る」コードを並べ、
// 案 A と案 B で診断が出るかを比べる。どれも今のコードが止めていない書き方。

import Foundation
import TUIKit

/// 1. コンポーネントの状態を、別の `Task` から書き換える。
public final class ProbeMutatesOwnStateFromTask: Component {

    private var count = 0

    public init() {}

    public var body: some View { Text("\(count)") }

    /// 別の `Task` から自分の状態を書き換える。
    public func bumpFromTask() {
        Task { self.count += 1 }
    }
}

/// 2. ウィジェットの状態を、別スレッドから動かす。
///
/// - Parameters:
///   - state: 動かすリストの状態。
public func probeMovesListStateFromThread(_ state: ListState) {
    Thread.detachNewThread { state.moveDown() }
}

/// 3. 入力欄の状態を、別の `Task` から書き換える。
///
/// - Parameters:
///   - state: 書き換える入力欄の状態。
public func probeInsertsIntoTextFieldFromTask(_ state: TextFieldState) {
    Task { state.insert("x") }
}

/// 4. 端末へ、別の `Task` から書き出す。
///
/// - Parameters:
///   - terminal: 書き出す先の端末。
public func probeWritesToTerminalFromTask(_ terminal: Terminal) {
    Task {
        terminal.write("x")
        terminal.flush()
    }
}

/// 5. ビューを、別スレッドで描く。
///
/// - Parameters:
///   - view: 描くビュー。
public func probeRendersFromThread(_ view: Text) {
    Thread.detachNewThread {
        var buffer = Buffer(size: Size(width: 10, height: 1))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
    }
}

/// 6. コンポーネントを別の `Task` へ渡して、画面を組み立てる。
///
/// - Parameters:
///   - component: 組み立てるコンポーネント。
public func probeReadsBodyFromTask(_ component: ProbeMutatesOwnStateFromTask) {
    Task { _ = component.body }
}
