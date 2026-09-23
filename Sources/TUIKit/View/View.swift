/// レイアウト時に、余った領域をどれだけ引き取るかを表す。
///
/// 重みが 0 のビューは希望サイズのまま配置され、1 以上のビューが余白を重みに応じて分け合う。
public struct LayoutTraits: Hashable, Sendable {
    /// 横方向の重み。負の値は 0 に丸められる。
    public var horizontalFlex: Int
    /// 縦方向の重み。負の値は 0 に丸められる。
    public var verticalFlex: Int

    /// 縦横の重みを指定して作る。
    ///
    /// - Parameters:
    ///   - horizontalFlex: 横方向の重み。
    ///   - verticalFlex: 縦方向の重み。
    public init(horizontalFlex: Int = 0, verticalFlex: Int = 0) {
        self.horizontalFlex = max(0, horizontalFlex)
        self.verticalFlex = max(0, verticalFlex)
    }

    /// 希望サイズのまま配置される。
    public static let fixed = LayoutTraits()
    /// 両方向に伸びる。
    public static let flexible = LayoutTraits(horizontalFlex: 1, verticalFlex: 1)

    /// 指定した軸の重み。
    ///
    /// - Parameters:
    ///   - axis: 重みを取り出す軸。
    /// - Returns: その軸の重み。
    public func flex(on axis: Axis) -> Int {
        switch axis {
        case .horizontal: return horizontalFlex
        case .vertical: return verticalFlex
        }
    }
}

/// 画面へ描画できるもの。
///
/// 子を持つビューは、子の `sizeThatFits(_:context:)` と `render(into:rect:context:)` を直接呼ばず、
/// 受け取った `RenderContext` の同名のメソッドを通して呼ぶ。
@MainActor
public protocol View {
    /// `proposal` の範囲で希望するサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 希望するサイズ。
    /// - Note: 返す値は `proposal` を超えてもよいが、その場合はレイアウト側で切り詰められる。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size

    /// `rect` の領域へ描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    /// - Postcondition: `rect` の外のセルは書き換えない。`context.screen` を基準に重ねる
    ///   `ScreenOverlayView` だけが、この約束から外れる。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext)

    /// 余白の分配に関する性質。
    var layoutTraits: LayoutTraits { get }
}

extension View {
    /// 希望サイズのまま配置される。
    public var layoutTraits: LayoutTraits { .fixed }
}

/// 何も描画しないビュー。
public struct EmptyView: View {
    /// 何も描画しないビューを作る。
    public init() {}

    /// 大きさを持たない。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 常に `.zero`。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { .zero }

    /// 何も描画しない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {}
}

/// 領域全体を 1 文字で塗りつぶすビュー。
public struct Fill: View {
    /// 敷き詰める文字。
    public var character: Character
    /// 文字に付けるスタイル。
    public var style: Style

    /// 敷き詰める文字とスタイルを指定して作る。
    ///
    /// - Parameters:
    ///   - character: 敷き詰める文字。
    ///   - style: 文字に付けるスタイル。
    public init(_ character: Character = " ", style: Style = .plain) {
        self.character = character
        self.style = style
    }

    /// 両方向に伸びる。
    public var layoutTraits: LayoutTraits { .flexible }

    /// 提案された領域をそのまま受け取る。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: `proposal` と同じサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

    /// 領域全体を `character` で埋める。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        buffer.fill(rect, repeating: character, style: style)
    }
}

/// 余白を押し広げるビュー。
public struct Spacer: View {
    /// 最低限確保する長さ。
    public var minLength: Int

    /// 最低限確保する長さを指定して作る。
    ///
    /// - Parameters:
    ///   - minLength: 最低限確保する長さ。負の値は 0 に丸められる。
    public init(minLength: Int = 0) {
        self.minLength = max(0, minLength)
    }

    /// 両方向に伸びる。
    public var layoutTraits: LayoutTraits { .flexible }

    /// 最低限の長さだけを希望する。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 幅・高さがともに `minLength` のサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: minLength, height: minLength)
    }

    /// 何も描画しない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {}
}

/// 1 本の罫線。
public struct Divider: View {
    /// 罫線を伸ばす方向。
    public var axis: Axis
    /// 罫線に使う文字。
    public var character: Character
    /// 文字に付けるスタイル。
    public var style: Style

    /// 方向と文字を指定して罫線を作る。
    ///
    /// - Parameters:
    ///   - axis: 罫線を伸ばす方向。
    ///   - character: 罫線に使う文字。`nil` なら方向に合わせて `─` か `│` を使う。
    ///   - style: 文字に付けるスタイル。
    public init(axis: Axis = .horizontal, character: Character? = nil, style: Style = .plain) {
        self.axis = axis
        self.character = character ?? (axis == .horizontal ? "─" : "│")
        self.style = style
    }

    /// 罫線を伸ばす方向にだけ伸びる。
    public var layoutTraits: LayoutTraits {
        switch axis {
        case .horizontal: return LayoutTraits(horizontalFlex: 1, verticalFlex: 0)
        case .vertical: return LayoutTraits(horizontalFlex: 0, verticalFlex: 1)
        }
    }

    /// 罫線を伸ばす方向にいっぱいまで広がり、もう一方は 1 桁・1 行になる。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 希望するサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        switch axis {
        case .horizontal: return Size(width: proposal.width, height: 1)
        case .vertical: return Size(width: 1, height: proposal.height)
        }
    }

    /// 領域を `character` で埋めて罫線を引く。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        buffer.fill(rect, repeating: character, style: style)
    }
}
