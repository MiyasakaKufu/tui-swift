/// `VStack`・`HStack` が配ったあとに残る `Size` を引き取る割合を、横と縦の方向ごとに持つ型。
///
/// `LayoutTraits.flex(on:)` が 0 の `View` は `View.sizeThatFits(_:context:)` の戻り値のまま配置され、
/// 1 以上の `View` が、`VStack`・`HStack` が配ったあとに残る `Size` を `LayoutTraits.flex(on:)` の値に応じて分け合う。
public struct LayoutTraits: Hashable, Sendable {
    /// 横方向の、`HStack` が配ったあとに残る `Size` の幅を引き取る割合を表す整数。
    ///
    /// `VStack` の中では、1 以上なら `VStack` の幅いっぱいに広がる。負の値は 0 に丸められる。
    public var horizontalFlex: Int
    /// 縦方向の、`VStack` が配ったあとに残る `Size` の高さを引き取る割合を表す整数。
    ///
    /// `HStack` の中では、1 以上なら `HStack` の高さいっぱいに広がる。負の値は 0 に丸められる。
    public var verticalFlex: Int

    /// `horizontalFlex` と `verticalFlex` を指定して `LayoutTraits` を作る。
    ///
    /// - Parameters:
    ///   - horizontalFlex: `LayoutTraits.horizontalFlex` にする整数。
    ///   - verticalFlex: `LayoutTraits.verticalFlex` にする整数。
    public init(horizontalFlex: Int = 0, verticalFlex: Int = 0) {
        self.horizontalFlex = max(0, horizontalFlex)
        self.verticalFlex = max(0, verticalFlex)
    }

    /// `horizontalFlex`・`verticalFlex` がともに 0 の `LayoutTraits`。
    ///
    /// `View.layoutTraits(context:)` がこれを返す `View` は、`View.sizeThatFits(_:context:)` の戻り値のまま配置される。
    public static let fixed = LayoutTraits()
    /// `horizontalFlex`・`verticalFlex` がともに 1 の `LayoutTraits`。
    public static let flexible = LayoutTraits(horizontalFlex: 1, verticalFlex: 1)

    /// `axis` の方の `horizontalFlex` か `verticalFlex` を返す。
    ///
    /// - Parameters:
    ///   - axis: `horizontalFlex` と `verticalFlex` のどちらを返すかを決める軸。
    /// - Returns: `axis` が `.horizontal` なら `horizontalFlex`、`.vertical` なら `verticalFlex`。
    public func flex(on axis: Axis) -> Int {
        switch axis {
        case .horizontal: return horizontalFlex
        case .vertical: return verticalFlex
        }
    }
}

/// 画面へ描画できるもの。
///
/// `View` に準拠する型には 2 種類ある。`View.body` を持つ `View`（`View.body` で別の `View` を返す）と、
/// `PrimitiveView`（`View.body` を持たず、`View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` を自分で書く）。
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
/// `View.body` を持つ `View` は `body` だけを書けばよい。`View.sizeThatFits(_:context:)`・`View.render(into:rect:context:)`・
/// `View.layoutTraits(context:)` のデフォルトの実装は、`body` を `child` 引数として `RenderContext` の同じ名前のメソッド
/// （`RenderContext.sizeThatFits(of:index:proposal:)` など）に渡す。
///
/// 別の `View` の `View.sizeThatFits(_:context:)`・`View.render(into:rect:context:)`・`View.layoutTraits(context:)` は
/// 直接呼び出さない。`context` 引数で受け取った `RenderContext` の `RenderContext.sizeThatFits(of:index:proposal:)`・
/// `RenderContext.render(_:index:into:rect:)`・`RenderContext.layoutTraits(of:index:)` に、その `View` を
/// `child` 引数として渡して呼び出す。
@MainActor
public protocol View {
    /// `body` が返す `View` の型。`View` に準拠する型が `some View` で書けば推論される。`PrimitiveView` では `Never`。
    associatedtype Body: View

    /// この `View` を組み立てる `View`。
    ///
    /// - Note: `Application.draw()` の 1 回のうちに、`View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` で
    ///   何度も値を取得される。取得するたびに違う `View` を返すと、`View.sizeThatFits(_:context:)` で測った `View` と
    ///   `View.render(into:rect:context:)` で描いた `View` が食い違う。
    var body: Body { get }

    /// `proposal` の範囲で、この `View` の `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: この `View` の `Size`。
    /// - Note: 戻り値は `proposal` を超えてもよい。超えた分は、`VStack`・`HStack`・`ZStack`・`AlignedView` などが、
    ///   この `View` の `View.render(into:rect:context:)` に渡す `rect` 引数の矩形を、自分の `rect` 引数の矩形に
    ///   収めるときに切り詰める。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size

    /// `rect` の領域へ描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Postcondition: `rect` の外の `Cell` は書き換えない。`context.screen` を基準に重ねる
    ///   `ScreenOverlayView` だけが、この約束から外れる。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext)

    /// この `View` の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: この `View` の `LayoutTraits`。
    func layoutTraits(context: RenderContext) -> LayoutTraits
}

extension View {
    /// `body` の `View` の `View.sizeThatFits(_:context:)` の戻り値を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `body` の `View` の `View.sizeThatFits(_:context:)` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: body, index: 0, proposal: proposal)
    }

    /// `body` の `View` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(body, index: 0, into: &buffer, rect: rect)
    }

    /// `body` の `View` の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `body` の `View` の `View.layoutTraits(context:)` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: body, index: 0)
    }
}

/// `View.body` を持たず、`View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` を自分で書く `View`。
///
/// `Text` や `VStack` のように、`View.body` で別の `View` を返す形では書けない `View` がこれに準拠する。
///
/// - Warning: `View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` を必ず書く。
///   書かないと、`View.body` を持つ `View` 向けのデフォルトの実装が選ばれ、`body` の値を取得したところでプロセスが終了する。
@MainActor
public protocol PrimitiveView: View where Body == Never {}

extension PrimitiveView {
    /// `PrimitiveView` には無い `body`。
    ///
    /// - Precondition: 値を取得しない。取得するとプロセスが終了する。
    public var body: Never {
        fatalError("\(Self.self) は PrimitiveView なので body を持たない")
    }

    /// `VStack`・`HStack` が配ったあとに残る `Size` を引き取らない `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.fixed`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .fixed }
}

extension Never: PrimitiveView {
    /// `Never` 自身。
    public typealias Body = Never

    /// `Never` のインスタンスは存在しないため、値を取得されることのない `body`。
    public var body: Never { switch self {} }

    /// `Never` のインスタンスは存在しないので呼び出されない。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `Size` を返すことはない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { switch self {} }

    /// `Never` のインスタンスは存在しないので呼び出されない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {}
}

/// 何も描画しない `View`。
public struct EmptyView: PrimitiveView {
    /// 何も描画しない `View` を作る。
    public init() {}

    /// 大きさを持たない。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.zero`。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { .zero }

    /// 何も描画しない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {}
}

/// 領域全体を 1 文字で塗りつぶす `View`。
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

    /// `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` がともに 1 の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.flexible`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .flexible }

    /// `proposal` をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `proposal` と同じサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

    /// 領域全体を `character` で埋める。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        buffer.fill(rect, repeating: character, style: style)
    }
}

/// `VStack`・`HStack` が配ったあとに残る `Size` を引き取る `View`。
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

    /// `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` がともに 1 の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.flexible`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .flexible }

    /// 幅・高さがともに `minLength` の `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 幅・高さがともに `minLength` の `Size`。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: minLength, height: minLength)
    }

    /// 何も描画しない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
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

    /// `axis` が `.horizontal` なら `LayoutTraits.horizontalFlex` だけが 1、`.vertical` なら `LayoutTraits.verticalFlex` だけが 1 の
    /// `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `axis` が `.horizontal` なら `LayoutTraits.horizontalFlex` だけが 1、`.vertical` なら `LayoutTraits.verticalFlex` だけが 1 の
    ///   `LayoutTraits`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        switch axis {
        case .horizontal: return LayoutTraits(horizontalFlex: 1, verticalFlex: 0)
        case .vertical: return LayoutTraits(horizontalFlex: 0, verticalFlex: 1)
        }
    }

    /// `axis` の方向は `proposal` と同じ長さ、もう一方は 1 の `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `axis` が `.horizontal` なら幅が `proposal.width` で高さが 1、
    ///   `.vertical` なら幅が 1 で高さが `proposal.height` の `Size`。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        switch axis {
        case .horizontal: return Size(width: proposal.width, height: 1)
        case .vertical: return Size(width: 1, height: proposal.height)
        }
    }

    /// 領域を `character` で埋めて罫線を引く。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        buffer.fill(rect, repeating: character, style: style)
    }
}
