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
        "スクロールするリスト",
        "テキスト入力",
        "フォーカスの移動と配送",
        "ウィンドウサイズ変更への追従",
    ]

    private let listState = ListState()
    private let nameState = TextFieldState()
    private let noteState = TextFieldState()
    private let focusManager = FocusManager()
    private var progress = 0.35
    private var lastEventDescription = "（まだ入力はありません）"
    private var terminalSize = Size(width: 0, height: 0)

    var focus: FocusManager? { focusManager }

    var body: some View {
        VStack(spacing: 0) {
            header()
            HStack(spacing: 1) {
                ListView(items: items, state: listState)
                    .padding(horizontal: 1)
                    .border(.rounded, style: borderStyle(for: listState), title: "機能一覧")
                    .focusable(listState, in: focusManager)
                    .flexible(horizontal: 2, vertical: 1)

                detail()
                    .border(.rounded, title: "詳細")
                    .flexible(horizontal: 3, vertical: 1)
            }
            .flexible(horizontal: 1, vertical: 1)
            footer()
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
            Text("選択中: \(selected)", wrap: .word).bold()
            Text("端末サイズ: \(terminalSize.width) x \(terminalSize.height)").dim()
            Text("ルートまで届いたイベント: \(lastEventDescription)", wrap: .word)

            VStack(spacing: 0) {
                Text("進捗（+ / - で増減）").dim()
                ProgressBar(value: progress, showsPercentage: true)
            }

            field(state: nameState, title: "名前", placeholder: "名前を入力…")
            field(state: noteState, title: "メモ", placeholder: "メモを入力…")

            Spacer()
        }
        .padding(horizontal: 1)
    }

    private func field(state: TextFieldState, title: String, placeholder: String) -> some View {
        TextField(
            state: state,
            placeholder: placeholder,
            showsCursor: !focusManager.isFocused(state)
        )
            .padding(horizontal: 1)
            .border(.single, style: borderStyle(for: state), title: title)
            .focusable(state, in: focusManager)
    }

    /// フォーカスの有無で枠線の色を変える。
    ///
    /// - Parameters:
    ///   - target: 枠線で囲むウィジェットの状態。
    /// - Returns: フォーカス中なら黄色、そうでなければ暗い灰色のスタイル。
    private func borderStyle(for target: FocusTarget) -> Style {
        Style(foreground: focusManager.isFocused(target) ? .yellow : .brightBlack)
    }

    private func footer() -> some View {
        HStack(spacing: 2) {
            Text(" ↑↓/jk 選択 ").styled(Style(foreground: .black, background: .white))
            Text(" ホイール スクロール ").styled(Style(foreground: .black, background: .white))
            Text(" Tab/クリック フォーカス ").styled(Style(foreground: .black, background: .white))
            Text(" Ctrl+Z 一時停止 ").styled(Style(foreground: .black, background: .white))
            Text(" Esc 終了 ").styled(Style(foreground: .black, background: .white))
            Spacer()
        }
        .frame(height: 1)
        .flexible(horizontal: 1, vertical: 0)
    }

    func handle(_ event: InputEvent) -> EventResult {
        lastEventDescription = describe(event)

        switch event {
        case .resize(let size):
            terminalSize = size
            return .handled
        case .key(let keyEvent):
            switch keyEvent.key {
            case .character("q"), .escape:
                return .quit
            case .character("+"):
                progress = min(1.0, progress + 0.05)
                return .handled
            case .character("-"):
                progress = max(0.0, progress - 0.05)
                return .handled
            default:
                return .ignored
            }
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
