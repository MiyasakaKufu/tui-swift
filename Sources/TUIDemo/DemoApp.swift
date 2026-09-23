import TUIKit

/// TUIKit の主な機能を一通り触れるデモ。
///
///   swift run tui-demo
@main
final class DemoApp: TerminalApp {
    static var options: ApplicationOptions {
        // 読み込みが終わった時点で画面が描き直されることを、このデモは示している。
        // frameInterval を設定すると、入力が無くても描き直されるので示せなくなる。
        ApplicationOptions(
            mouseTracking: .motion,
            reportsFocus: true,
            windowTitle: "TUIKit デモ",
            cursorShape: .blinkingBar
        )
    }

    /// 外部から届くイベント。
    enum Message: Sendable {
        /// 一覧の読み込みが終わった。
        case itemsLoaded([String])
    }

    private static let placeholderItems = ["読み込み中…"]

    private static let loadedItems = [
        "差分レンダリング",
        "全角文字・絵文字の幅計算",
        "キー入力とマウスの解析",
        "VStack / HStack によるレイアウト",
        "枠線とタイトル",
        "スクロールするリスト",
        "テキスト入力",
        "ウィンドウサイズ変更への追従",
        "ビューの重ね描きとダイアログ",
        "外部イベントによる更新",
    ]

    private static let simulatedLoadDuration = Duration.milliseconds(800)

    private var items = DemoApp.placeholderItems
    private var isLoaded = false

    private let listState = ListState()
    private let inputState = TextFieldState()
    private var progress = 0.35
    private var lastEventDescription = "（まだ入力はありません）"
    private var isEditing = false
    private var isShowingDialog = false
    private var terminalSize = Size(width: 0, height: 0)

    var body: some View {
        VStack(spacing: 0) {
            header()
            HStack(spacing: 1) {
                ListView(items: items, state: listState)
                    .padding(horizontal: 1)
                    .border(.rounded, title: "機能一覧")
                    .flexible(horizontal: 2, vertical: 1)

                detail()
                    .border(.rounded, title: "詳細")
                    .flexible(horizontal: 3, vertical: 1)
            }
            .flexible(horizontal: 1, vertical: 1)
            footer()
        }
        .screenOverlay(dialog())
    }

    private func dialog() -> some View {
        let textStyle = Style(foreground: .brightWhite, background: .blue)
        return ZStack {
            if isShowingDialog {
                VStack(spacing: 1, alignment: .center) {
                    Text("画面の中央に重ねたダイアログです。", style: textStyle, wrap: .word)
                    Text("下に敷いた全角文字を覆っても、行の桁はずれません。", style: textStyle, wrap: .word)
                    Text("Enter か Esc で閉じる", style: textStyle).dim()
                }
                .padding(horizontal: 2, vertical: 1)
                .border(.double, style: Style(foreground: .yellow, background: .blue), title: "ダイアログ")
                .background(style: Style(background: .blue))
                .frame(width: 44, height: 9)
            }
        }
    }

    private func header() -> some View {
        Text(" TUIKit デモ ", style: Style(foreground: .black, background: .cyan).bold)
            .frame(height: 1)
            .background(style: Style(background: .cyan))
            .flexible(horizontal: 1, vertical: 0)
    }

    private func detail() -> some View {
        let selected = items.indices.contains(listState.selectedIndex)
            ? items[listState.selectedIndex]
            : "-"

        return VStack(spacing: 1) {
            Text(isLoaded ? "選択中: \(selected)" : "一覧を読み込んでいます…", wrap: .word).bold()
            Text("端末サイズ: \(terminalSize.width) x \(terminalSize.height)").dim()
            Text("直前のイベント: \(lastEventDescription)", wrap: .word)

            VStack(spacing: 0) {
                Text("進捗（+ / - で増減）").dim()
                ProgressBar(value: progress, showsPercentage: true)
            }

            VStack(spacing: 0) {
                Text(isEditing ? "入力中（Tab で戻る）" : "Tab で入力に切り替え").dim()
                TextField(
                    state: inputState,
                    placeholder: "ここに入力…",
                    showsCursor: !isEditing
                )
                    .padding(horizontal: 1)
                    .border(.single, style: Style(foreground: isEditing ? .yellow : .brightBlack))
            }

            Spacer()
        }
        .padding(horizontal: 1)
    }

    private func footer() -> some View {
        HStack(spacing: 2) {
            Text(" ↑↓/jk 選択 ").styled(Style(foreground: .black, background: .white))
            Text(" ホイール スクロール ").styled(Style(foreground: .black, background: .white))
            Text(" Tab 切り替え ").styled(Style(foreground: .black, background: .white))
            Text(" d ダイアログ ").styled(Style(foreground: .black, background: .white))
            Text(" Ctrl+Z 一時停止 ").styled(Style(foreground: .black, background: .white))
            Text(" q 終了 ").styled(Style(foreground: .black, background: .white))
            Spacer()
        }
        .frame(height: 1)
        .flexible(horizontal: 1, vertical: 0)
    }

    /// 起動したら一覧を読み込む。
    var startupEffect: Effect<Message> {
        let duration = DemoApp.simulatedLoadDuration
        let loaded = DemoApp.loadedItems
        return .run {
            try? await Task.sleep(for: duration)
            return .itemsLoaded(loaded)
        }
    }

    func receive(_ message: Message) -> EventResult {
        switch message {
        case .itemsLoaded(let loaded):
            items = loaded
            isLoaded = true
            lastEventDescription = "一覧の読み込みが終わりました（\(loaded.count) 件）"
            return .handled
        }
    }

    var cursorPosition: Point? {
        isEditing ? inputState.renderedCursorPoint : nil
    }

    func handle(_ event: InputEvent) -> EventResult {
        lastEventDescription = describe(event)

        if case .resize(let size) = event {
            terminalSize = size
            return .handled
        }

        if isShowingDialog {
            if case .key = event {
                isShowingDialog = false
                return .handled
            }
            return .ignored
        }

        if case .key(let keyEvent) = event {
            if keyEvent.key == .tab {
                isEditing.toggle()
                return .handled
            }
            if isEditing {
                if keyEvent.key == .escape {
                    isEditing = false
                    return .handled
                }
                return inputState.handle(event) ? .handled : .ignored
            }
            switch keyEvent.key {
            case .character("q"), .escape:
                return .quit
            case .character("d"):
                isShowingDialog = true
                return .handled
            case .character("+"):
                progress = min(1.0, progress + 0.05)
                return .handled
            case .character("-"):
                progress = max(0.0, progress - 0.05)
                return .handled
            default:
                break
            }
        }

        if isEditing, case .paste = event {
            return inputState.handle(event) ? .handled : .ignored
        }

        guard isLoaded else { return .ignored }
        return listState.handle(event) ? .handled : .ignored
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
            // ボタンを伴うイベントでは種類も出す。拡張ボタン（戻る・進む）を
            // 左ボタンと見分けるために必要。ホイールは `.none` なので出ない。
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
