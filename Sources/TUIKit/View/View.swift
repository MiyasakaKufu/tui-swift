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
/// ビューには 2 種類ある。`body` で別のビューを組み合わせる合成ビューと、
/// `sizeThatFits(_:context:)` と `render(into:rect:context:)` を自分で書くプリミティブ（`PrimitiveView`）。
///
/// ```swift
/// struct Greeting: View {
///     let name: String
///
///     var body: some View {
///         Text("こんにちは、\(name)").bold()
///     }
/// }
/// ```
///
/// 合成ビューは `body` だけを書けばよい。測定・描画・余白の分配は `body` のビューに任される。
///
/// 子を持つビューは、子の `sizeThatFits(_:context:)`・`render(into:rect:context:)`・
/// `layoutTraits(context:)` を直接呼ばず、受け取った `RenderContext` の同名のメソッドを通して呼ぶ。
@MainActor
public protocol View {
    /// `body` が返すビューの型。適合側が `some View` で書けば推論される。プリミティブでは `Never`。
    associatedtype Body: View

    /// このビューを組み立てるビュー。
    ///
    /// - Note: 1 フレームのうちに、測定と描画で何度も読まれる。読むたびに違うビューを返すと、
    ///   測ったときと描いたときで中身が食い違う。
    var body: Body { get }

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

    /// 余白の分配に関する性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 余白の分配に関する性質。
    func layoutTraits(context: RenderContext) -> LayoutTraits
}

extension View {
    /// `body` のビューが希望するサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: `body` のビューが希望するサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: body, index: 0, proposal: proposal)
    }

    /// `body` のビューを描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(body, index: 0, into: &buffer, rect: rect)
    }

    /// `body` のビューの性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: `body` のビューの、余白の分配に関する性質。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: body, index: 0)
    }
}

/// `body` を持たず、自分で測定と描画を行うビュー。
///
/// `Text` や `VStack` のように、別のビューの組み合わせでは表せないビューがこれに適合する。
///
/// - Warning: `sizeThatFits(_:context:)` と `render(into:rect:context:)` を必ず書く。
///   書かないと、合成ビュー向けの既定の実装が選ばれ、`body` を読んだところで止まる。
@MainActor
public protocol PrimitiveView: View where Body == Never {}

extension PrimitiveView {
    /// プリミティブには無い `body`。
    ///
    /// - Precondition: 読まない。読むとプログラムが止まる。
    public var body: Never {
        fatalError("\(Self.self) はプリミティブなので body を持たない")
    }

    /// 希望サイズのまま配置される性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 常に `.fixed`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .fixed }
}

extension Never: PrimitiveView {
    /// `Never` 自身。
    public typealias Body = Never

    /// 値が存在しないため、読まれることのない `body`。
    public var body: Never { switch self {} }

    /// 値が存在しないので呼ばれない。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 返らない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { switch self {} }

    /// 値が存在しないので呼ばれない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {}
}

/// 何も描画しないビュー。
public struct EmptyView: PrimitiveView {
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
public struct Fill: PrimitiveView {
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

    /// 両方向に伸びる性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 常に `.flexible`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .flexible }

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
public struct Spacer: PrimitiveView {
    /// 最低限確保する長さ。
    public var minLength: Int

    /// 最低限確保する長さを指定して作る。
    ///
    /// - Parameters:
    ///   - minLength: 最低限確保する長さ。負の値は 0 に丸められる。
    public init(minLength: Int = 0) {
        self.minLength = max(0, minLength)
    }

    /// 両方向に伸びる性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 常に `.flexible`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .flexible }

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
public struct Divider: PrimitiveView {
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

    /// 罫線を伸ばす方向にだけ伸びる性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: `axis` の方向の重みだけが 1 の性質。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
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
