import Foundation
import TUIKit

/// TUIKit の主な機能を一通り触れるデモ。
///
///   swift run tui-demo
@main
final class DemoApp: TerminalApp {
    static var options: ApplicationOptions {
        ApplicationOptions(
            mouseTracking: .motion,
            reportsFocus: true,
            windowTitle: "TUIKit デモ",
            cursorShape: .blinkingBar
        )
    }

    private let items = [
        "差分レンダリング",
        "全角文字・絵文字の幅計算",
        "キー入力とマウスの解析",
        "VStack / HStack によるレイアウト",
        "枠線とタイトル",
        "ListView のスクロール",
        "TextField での入力",
        "Tab とクリックによるフォーカスの移動",
        "ウィンドウサイズ変更への追従",
        "View の重ね描きとダイアログ",
    ]

    /// ``DemoApp/task(sender:)`` が送る値。
    enum Message: Sendable {
        /// 1 秒たった。
        case tick
    }

    private(set) var isFinished = false
    private var progress: Double
    private var lastEventDescription = "（まだ入力はありません）"
    private var terminalSize = Size(width: 0, height: 0)
    private var secondsSinceLaunch = 0
    private var resumeCount = 0

    /// 前回の終了時に保存した進捗を読み込んで作る。
    init() {
        progress = DemoState.loadProgress() ?? 0.35
    }

    var body: some View {
        DemoScreen(
            items: items,
            progress: progress,
            lastEventDescription: lastEventDescription,
            terminalSize: terminalSize,
            secondsSinceLaunch: secondsSinceLaunch,
            resumeCount: resumeCount
        )
        .tint(.green)
    }

    func task(sender: MessageSender<Message>) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            sender.send(.tick)
        }
    }

    func receive(_ message: Message) -> EventResult {
        switch message {
        case .tick:
            secondsSinceLaunch += 1
        }
        return .handled
    }

    func willSuspend() {
        // 保存を `didTerminate(_:)` だけに任せてはいけない。一時停止したまま SIGKILL で終わらされると呼び出されず、進捗が失われる。
        DemoState.saveProgress(progress)
    }

    func didResume() {
        resumeCount += 1
    }

    func didTerminate(_ reason: TerminationReason) {
        DemoState.saveProgress(progress)
        print("進捗 \(Int((progress * 100).rounded()))% を \(DemoState.fileURL.path) に保存しました。次の起動で読み込みます。")
    }

    func handle(_ event: InputEvent) -> EventResult {
        lastEventDescription = describe(event)

        if case .resize(let size) = event {
            terminalSize = size
            return .handled
        }

        guard case .key(let keyEvent) = event else { return .ignored }
        switch keyEvent.key {
        case .character("q"), .escape:
            isFinished = true
            return .handled
        case .character("+"):
            progress = min(1.0, progress + 0.05)
            return .handled
        case .character("-"):
            progress = max(0.0, progress - 0.05)
            return .handled
        default:
            return .ignored
        }
    }

    private func describe(_ event: InputEvent) -> String {
        switch event {
        case .key(let keyEvent):
            var parts: [String] = []
            if keyEvent.modifiers.contains(.control) { parts.append("Ctrl") }
            if keyEvent.modifiers.contains(.alt) { parts.append("Alt") }
            if keyEvent.modifiers.contains(.shift) { parts.append("Shift") }
            parts.append(name(of: keyEvent.key))
            return parts.joined(separator: "+")
        case .mouse(let mouseEvent):
            var parts = ["マウス", "\(mouseEvent.action)"]
            // `MouseEvent.button` を出すのをやめると、拡張ボタン（戻る・進む）の押下が左ボタンの押下と同じ表示になり見分けられない。
            if mouseEvent.button != .none { parts.append("\(mouseEvent.button)") }
            parts.append("(\(mouseEvent.position.x), \(mouseEvent.position.y))")
            return parts.joined(separator: " ")
        case .resize(let size):
            return "リサイズ \(size.width)x\(size.height)"
        case .paste(let text):
            return "貼り付け \(text.count) 文字"
        case .focus(let gained):
            return gained ? "フォーカス取得" : "フォーカス喪失"
        }
    }

    private func name(of key: Key) -> String {
        switch key {
        case .character(let character): return String(character)
        case .function(let number): return "F\(number)"
        default: return String(describing: key)
        }
    }
}

/// 進捗を、終了時にファイルへ保存し、起動時に読み込む型。
private enum DemoState {
    /// 進捗を置くファイルの URL。
    static let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("tui-demo-progress")

    /// 保存した進捗を読み込む。
    ///
    /// - Returns: 保存した進捗。ファイルが無いか、読めなければ `nil`。
    static func loadProgress() -> Double? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return min(1.0, max(0.0, value))
    }

    /// 進捗を保存する。書き込めなければ何もしない。
    ///
    /// - Parameters:
    ///   - progress: 保存する進捗。
    static func saveProgress(_ progress: Double) {
        try? String(progress).write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

/// 画面上端の見出し。
private struct Header: View {
    var body: some View {
        Text(" TUIKit デモ ")
            .foregroundStyle(.black)
            .bold()
            .frame(height: 1)
            .background(.cyan)
            .flexible(horizontal: 1, vertical: 0)
    }
}

/// 機能一覧と詳細を並べ、ダイアログを重ねる画面。
private struct DemoScreen: View {
    enum Field: Hashable {
        case list
        case name
        case note
    }

    let items: [String]
    let progress: Double
    let lastEventDescription: String
    let terminalSize: Size
    let secondsSinceLaunch: Int
    let resumeCount: Int

    @State private var selection = 0
    @State private var name = ""
    @State private var note = ""
    @State private var listState = ListState()
    @State private var nameState = TextFieldState()
    @State private var noteState = TextFieldState()
    @State private var isShowingDialog = false
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 0) {
            Header()
            HStack(spacing: 1) {
                ListView(items: items, selection: $selection, state: listState)
                    .padding(horizontal: 1)
                    .border(.rounded, color: borderColor(for: .list), title: "機能一覧")
                    .focused($focusedField, equals: .list)
                    .onKeyPress(.character("d")) {
                        isShowingDialog = true
                        return .handled
                    }
                    .flexible(horizontal: 2, vertical: 1)

                detail
                    .border(.rounded, title: "詳細")
                    .flexible(horizontal: 3, vertical: 1)
            }
            .flexible(horizontal: 1, vertical: 1)
            Footer()
        }
        .sheet(isPresented: $isShowingDialog) {
            Dialog(isShowing: $isShowingDialog)
        }
    }

    /// 選択中の項目と入力の状態を並べる欄。
    private var detail: some View {
        VStack(spacing: 1) {
            Text("選択中: \(items.indices.contains(selection) ? items[selection] : "-")", wrap: .word).bold()
            Text("ウィンドウサイズ: \(terminalSize.width) x \(terminalSize.height)").foregroundStyle(.secondary)
            Text("TerminalApp.handle(_:) に届いた入力: \(lastEventDescription)", wrap: .word)
            Text("起動してから \(secondsSinceLaunch) 秒（TerminalApp.task(sender:) が 1 秒ごとに送る）", wrap: .word)
                .foregroundStyle(.secondary)
            Text("一時停止から再開した回数: \(resumeCount)").foregroundStyle(.secondary)

            VStack(spacing: 0) {
                Text("進捗（一覧で + / - を押すと増減。終了時に保存）").foregroundStyle(.secondary)
                ProgressBar(value: progress, showsPercentage: true)
            }

            VStack(spacing: 0) {
                Text("名前（\(name.count) 文字）").foregroundStyle(.secondary)
                TextField(text: $name, state: nameState, placeholder: "ここに入力…")
                    .padding(horizontal: 1)
                    .border(.single, color: borderColor(for: .name))
                    .focused($focusedField, equals: .name)
                    .onKeyPress(.enter) {
                        focusedField = .note
                        return .handled
                    }
            }

            VStack(spacing: 0) {
                Text("メモ（Enter で一覧へ戻る）").foregroundStyle(.secondary)
                TextField(text: $note, state: noteState, placeholder: "ここに入力…")
                    .padding(horizontal: 1)
                    .border(.single, color: borderColor(for: .note))
                    .focused($focusedField, equals: .note)
                    .onKeyPress(.enter) {
                        focusedField = .list
                        return .handled
                    }
            }

            Spacer()
        }
        .padding(horizontal: 1)
    }

    /// `field` がフォーカスを持つ間だけ目立たせる、枠線の文字色を返す。
    ///
    /// - Parameters:
    ///   - field: 枠線で囲む欄。
    /// - Returns: `field` がフォーカスを持てば `.yellow`、持たなければ `.brightBlack`。
    private func borderColor(for field: Field) -> Color {
        focusedField == field ? .yellow : .brightBlack
    }
}

/// 画面下端の操作の一覧。
private struct Footer: View {
    private let hints = [
        "Tab / クリック 移動",
        "↑↓/jk 選択",
        "ホイール スクロール",
        "d ダイアログ（一覧で）",
        "Ctrl+Z 一時停止",
        "Esc 終了",
    ]

    var body: some View {
        HStack(spacing: 2) {
            for hint in hints {
                Text(" \(hint) ").foregroundStyle(.black).background(.white)
            }
            Spacer()
        }
        .frame(height: 1)
        .flexible(horizontal: 1, vertical: 0)
    }
}

/// 画面の中央に重ねるダイアログ。
private struct Dialog: View {
    let isShowing: Binding<Bool>
    @State private var buttonState = ListState()

    var body: some View {
        VStack(spacing: 1, alignment: .center) {
            Text("View.sheet(isPresented:content:) で重ねたダイアログです。", wrap: .word)
            Text("表示している間、後ろの欄へは入力が渡りません。", wrap: .word)
            ListView(items: ["閉じる"], state: buttonState, selectionMarker: "")
                .frame(width: 6, height: 1)
                .onKeyPress(.enter) {
                    isShowing.wrappedValue = false
                    return .handled
                }
                .onKeyPress(.escape) {
                    isShowing.wrappedValue = false
                    return .handled
                }
        }
        .foregroundStyle(.brightWhite)
        .padding(horizontal: 2, vertical: 1)
        .border(.double, color: .yellow, title: "ダイアログ")
        .background(.blue)
        .frame(width: 48, height: 11)
    }
}
