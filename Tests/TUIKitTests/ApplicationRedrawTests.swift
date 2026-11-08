import Foundation
import XCTest
@testable import TUIKit

/// TUIKit が呼び出したコードの外で状態を変えても、`ApplicationOptions.frameInterval` なしで再描画されるかを、疑似端末（pty）の上で確かめる。
@MainActor
final class ApplicationRedrawTests: XCTestCase {

    /// `TerminalApp.body` に付けた `View.task(_:)` のクロージャで、`TerminalApp` に準拠する型の `State` を付けたプロパティへ代入すると、再描画される。
    func testAssigningAppStateInTaskRedraws() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let application = Application(root: LoadingApp(), options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // 描き直されたかを、キーを書いた後で確かめてはいけない。キーで描き直されたのかどうかが分からなくなる。
        let redrew = await waitUntil { pty.output.contains("LOADED") }
        XCTAssertTrue(redrew, "View.task(_:) のクロージャで代入した値が画面に出ない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// `View.onKeyPress(_:action:)` のクロージャから作った `Task` の中で、`View` の `State` を付けたプロパティへ代入すると、再描画される。
    func testAssigningViewStateInTaskFromKeyPressRedraws() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let application = Application(root: SearchApp(), options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // 最初の描画より前に書いてはいけない。フォーカスを持つ `View` が決まる前にキーが届き、`View.onKeyPress(_:action:)` のクロージャが呼び出されない。
        let drew = await waitUntil { pty.output.contains("IDLE") }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        pty.write(UInt8(ascii: "s"))
        let redrew = await waitUntil { pty.output.contains("FOUND") }
        XCTAssertTrue(redrew, "Task の中で代入した値が画面に出ない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// `View.onChange(of:_:)` のクロージャが変えた値を、別の `View.onChange(of:_:)` が見つけて変えた値も、画面に出る。
    func testChainedOnChangeActionsReachScreen() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = ChainedChangeApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.recorder.drawnText == "third=0" }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        pty.write(UInt8(ascii: "+"))
        // キーを 1 つ書いた後に、もう 1 つ書いてはいけない。そのキーで再描画されて、連鎖の最後の値が出ることになる。
        let reached = await waitUntil { app.recorder.drawnText == "third=1" }
        XCTAssertTrue(reached, "2 つ目の View.onChange(of:_:) のクロージャで変えた値が画面に出ない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// `View.task(_:)` のクロージャで `TerminalApp.isFinished` を `true` にすると、`TerminalApp.body` が読んでいなくても、キーを待たずにループが終わる。
    func testFinishingInTaskEndsLoopWithoutKeys() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let application = Application(root: TaskFinishingApp(), options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await waitForLoop(loop)
    }

    /// `View.task(_:)` のクロージャで `FocusState` を付けたプロパティへ代入すると、フォーカスが移り、再描画される。
    func testAssigningFocusStateInTaskRedraws() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = FocusMovingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let redrew = await waitUntil { app.recorder.drawnText == "focus=second" }
        XCTAssertTrue(redrew, "View.task(_:) のクロージャで移したフォーカスが画面に出ない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// 1 つの `Task` の中で続けて何度代入しても、再描画するのは 1 回だけ。
    func testManyAssignmentsWithoutSuspensionRedrawOnce() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = CountingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let finished = await waitUntil { app.recorder.drawnText == "count=100" }
        XCTAssertTrue(finished, "代入した値が画面に出ない")
        // 待たずに数えてはいけない。余分な再描画は後の周回で起きるので、見逃す。
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(app.recorder.drawCount, 2)

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// `TerminalApp.handle(_:)` の中で、描くときに読んだ値へ代入しても、再描画するのは 1 回だけ。
    func testAssigningInHandleRedrawsOnce() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = CountingApp(countsOnKey: true)
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.recorder.drawnText == "count=0" }
        XCTAssertTrue(drew, "最初の描画が終わらない")
        let drawsBefore = app.recorder.drawCount

        pty.write(UInt8(ascii: "+"))
        let redrew = await waitUntil { app.recorder.drawnText == "count=1" }
        XCTAssertTrue(redrew, "キーで代入した値が画面に出ない")
        // 待たずに数えてはいけない。余分な再描画は後の周回で起きるので、見逃す。
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(app.recorder.drawCount - drawsBefore, 1)

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    // MARK: - 補助

    /// 問い合わせを送らず、代替画面へも切り替えない設定。
    private var testOptions: ApplicationOptions {
        ApplicationOptions(
            usesAlternateScreen: false,
            usesBracketedPaste: false,
            usesKeyboardProtocol: false
        )
    }

    /// 条件が満たされるまで待つ。
    ///
    /// - Parameters:
    ///   - timeout: 待つ秒数の上限。
    ///   - condition: 満たされたかを返す処理。
    /// - Returns: 時間内に満たされれば `true`。
    private func waitUntil(timeout: Double = 5, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            // `Thread.sleep` で待つと、アクタが止まってイベントループが進まない。
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }
}

/// `q` を受け取ったら `isFinished` を `true` にする。
///
/// - Parameters:
///   - event: 受け取った ``InputEvent``。
///   - isFinished: `true` にする ``Binding``。
/// - Returns: `q` なら `.handled`、それ以外は `.ignored`。
@MainActor
private func finish(on event: InputEvent, _ isFinished: Binding<Bool>) -> EventResult {
    guard case .key(let keyEvent) = event, keyEvent.key == .character("q") else { return .ignored }
    isFinished.wrappedValue = true
    return .handled
}

/// 読み込みを模して少し待つ。
private func simulateLoading() async {
    // 待つのをやめてはいけない。最初の描画と同じ周回で値が変わり、状態の変化で再描画されたのかどうかが分からなくなる。
    try? await Task.sleep(nanoseconds: 50_000_000)
}

// 描いた値を疑似端末の出力で確かめたくなるが、`Renderer` は変わった `Cell` だけを書き出すので、`count=0` から `count=1` に変わっても `count=1` は出力に現れない。
/// テスト用の `TerminalApp` に準拠する型が、`TerminalApp.body` を評価するたびに書き込むクラス。
@MainActor
private final class DrawRecorder {
    /// `TerminalApp.body` が評価された回数。
    var drawCount = 0
    /// 最後に評価した `TerminalApp.body` が描く、確かめたい文字列。
    var drawnText = ""
}

/// `View.task(_:)` のクロージャで、自分の `State` を付けたプロパティへ読み込んだ値を代入する `TerminalApp` に準拠する型。
private struct LoadingApp: TerminalApp {
    @State private(set) var isFinished = false
    @State private var status = "WAITING"

    var body: some View {
        Text(status).task {
            await simulateLoading()
            status = "LOADED"
        }
    }

    func handle(_ event: InputEvent) -> EventResult {
        finish(on: event, $isFinished)
    }
}

/// `s` を受け取ったら、`Task` の中で検索を模して結果を `State` を付けたプロパティへ代入する `View`。
private struct SearchView: View {
    @State private var result = "IDLE"
    @State private var listState = ListState()

    var body: some View {
        VStack {
            Text(result)
            ListView(items: ["項目"], state: listState)
        }
        .onKeyPress(.character("s")) {
            Task {
                await simulateLoading()
                result = "FOUND"
            }
            return .handled
        }
    }
}

/// ``SearchView`` を描く `TerminalApp` に準拠する型。
private struct SearchApp: TerminalApp {
    @State private(set) var isFinished = false

    var body: some View {
        SearchView()
    }

    func handle(_ event: InputEvent) -> EventResult {
        finish(on: event, $isFinished)
    }
}

/// `+` で `first` を増やすと、`View.onChange(of:_:)` で `second`、さらに `third` へ値が伝わる `TerminalApp` に準拠する型。
private struct ChainedChangeApp: TerminalApp {
    /// 描いた `third` を書き込む先。
    let recorder = DrawRecorder()
    @State private(set) var isFinished = false
    @State private var first = 0
    @State private var second = 0
    @State private var third = 0

    var body: some View {
        recorder.drawnText = "third=\(third)"
        return VStack {
            Text("first=\(first)")
                .onChange(of: first) { second = first }
            Text("second=\(second)")
                .onChange(of: second) { third = second }
            Text("third=\(third)")
        }
    }

    func handle(_ event: InputEvent) -> EventResult {
        if case .key(let keyEvent) = event, keyEvent.key == .character("+") {
            first += 1
            return .handled
        }
        return finish(on: event, $isFinished)
    }
}

/// `View.task(_:)` のクロージャで `isFinished` を `true` にする `TerminalApp` に準拠する型。`TerminalApp.body` では `isFinished` を読まない。
private struct TaskFinishingApp: TerminalApp {
    @State private(set) var isFinished = false

    var body: some View {
        let finish = $isFinished
        return Text("WAITING").task {
            await simulateLoading()
            finish.wrappedValue = true
        }
    }
}

/// `View.task(_:)` のクロージャで、2 つ目の `ListView` へフォーカスを移す `TerminalApp` に準拠する型。
private struct FocusMovingApp: TerminalApp {
    /// フォーカスを受け取る `ListView`。
    enum Field: Hashable {
        case first
        case second
    }

    /// 描いたフォーカスを書き込む先。
    let recorder = DrawRecorder()
    @State private(set) var isFinished = false
    @FocusState private var focus: Field?
    @State private var firstState = ListState()
    @State private var secondState = ListState()

    var body: some View {
        let text = focus == .second ? "focus=second" : "focus=other"
        recorder.drawnText = text
        return VStack {
            Text(text)
            ListView(items: ["1"], state: firstState).focused($focus, equals: .first)
            ListView(items: ["2"], state: secondState).focused($focus, equals: .second)
        }
        .task {
            await simulateLoading()
            focus = .second
        }
    }

    func handle(_ event: InputEvent) -> EventResult {
        finish(on: event, $isFinished)
    }
}

/// `count` を描く `TerminalApp` に準拠する型。
///
/// `countsOnKey` が `false` なら、`View.task(_:)` のクロージャで、中断を挟まずに `count` へ 100 回代入する。`true` なら、`+` を受け取るたびに `TerminalApp.handle(_:)` で 1 つ増やす。
private struct CountingApp: TerminalApp {
    /// `TerminalApp.body` の評価を数える先。
    let recorder = DrawRecorder()
    @State private(set) var isFinished = false
    @State private var count = 0
    private let countsOnKey: Bool

    /// 数え方を決めて作る。
    ///
    /// - Parameters:
    ///   - countsOnKey: `+` を受け取るたびに数えるなら `true`。`View.task(_:)` のクロージャで数えるなら `false`。
    init(countsOnKey: Bool) {
        self.countsOnKey = countsOnKey
    }

    /// `View.task(_:)` のクロージャで数えるものとして作る。
    init() {
        self.init(countsOnKey: false)
    }

    var body: some View {
        recorder.drawCount += 1
        recorder.drawnText = "count=\(self.count)"
        let countsOnKey = self.countsOnKey
        let count = $count
        return Text("count=\(self.count)").task {
            guard !countsOnKey else { return }
            await simulateLoading()
            for _ in 0..<100 { count.wrappedValue += 1 }
        }
    }

    func handle(_ event: InputEvent) -> EventResult {
        if countsOnKey, case .key(let keyEvent) = event, keyEvent.key == .character("+") {
            count += 1
            return .handled
        }
        return finish(on: event, $isFinished)
    }
}
