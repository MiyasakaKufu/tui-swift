/// `Cell` の位置を表す座標。原点は左上、`x` は横方向の位置、`y` は行を表す。
public struct Point: Hashable, Sendable {
    /// 横方向の位置。左端が 0。
    public var x: Int
    /// 行の位置。上端が 0。
    public var y: Int

    /// 座標を作る。
    ///
    /// - Parameters:
    ///   - x: 横方向の位置。
    ///   - y: 行の位置。
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// 原点。
    public static let zero = Point(x: 0, y: 0)

    /// 指定した分だけずらした座標を返す。
    ///
    /// - Parameters:
    ///   - dx: 横方向のずれ。
    ///   - dy: 行方向のずれ。
    /// - Returns: ずらした座標。
    public func offset(dx: Int = 0, dy: Int = 0) -> Point {
        Point(x: x + dx, y: y + dy)
    }
}

/// 横に並ぶ `Cell` の数と行数で表したサイズ。負の値は 0 に丸められる。
public struct Size: Hashable, Sendable {
    /// 横に並ぶ `Cell` の数。負の値は 0 に丸められる。
    public var width: Int {
        didSet { width = max(0, width) }
    }
    /// 行数。負の値は 0 に丸められる。
    public var height: Int {
        didSet { height = max(0, height) }
    }

    /// サイズを作る。
    ///
    /// - Parameters:
    ///   - width: 横に並ぶ `Cell` の数。
    ///   - height: 行数。
    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    /// 幅・高さがともに 0 のサイズ。
    public static let zero = Size(width: 0, height: 0)

    /// 幅と高さのどちらかが 0 か。
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// 各辺を `other` 以下に切り詰めたサイズ。
    ///
    /// - Parameters:
    ///   - other: 上限とするサイズ。
    /// - Returns: 幅・高さのそれぞれを `other` 以下にしたサイズ。
    public func clamped(to other: Size) -> Size {
        Size(width: min(width, other.width), height: min(height, other.height))
    }
}

/// 矩形領域。`maxX` / `maxY` は排他的（領域に含まれない）。
public struct Rect: Hashable, Sendable {
    /// 左上の座標。
    public var origin: Point
    /// 幅と高さ。
    public var size: Size

    /// 原点とサイズから矩形を作る。
    ///
    /// - Parameters:
    ///   - origin: 左上の座標。
    ///   - size: 幅と高さ。
    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    /// 座標とサイズの成分から矩形を作る。
    ///
    /// - Parameters:
    ///   - x: 左端の `Point.x`。
    ///   - y: 上端の行。
    ///   - width: 横に並ぶ `Cell` の数。
    ///   - height: 行数。
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    /// 原点にある、幅・高さが 0 の矩形。
    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    /// 横に並ぶ `Cell` の数。
    public var width: Int { size.width }
    /// 行数。
    public var height: Int { size.height }
    /// 左端の `Point.x`。
    public var minX: Int { origin.x }
    /// 上端の行。
    public var minY: Int { origin.y }
    /// 領域の右隣の `Point.x`。この位置の `Cell` は領域に含まれない。
    public var maxX: Int { origin.x + size.width }
    /// 下端の行。この行は領域に含まれない。
    public var maxY: Int { origin.y + size.height }
    /// 幅と高さのどちらかが 0 か。
    public var isEmpty: Bool { size.isEmpty }

    /// 座標が領域に含まれるか。
    ///
    /// - Parameters:
    ///   - point: 調べる座標。
    /// - Returns: 領域に含まれれば `true`。
    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// 別の矩形との共通部分。
    ///
    /// - Parameters:
    ///   - other: 重ね合わせる矩形。
    /// - Returns: 共通部分の矩形。重なりがなければ幅・高さが 0 の矩形。
    public func intersection(_ other: Rect) -> Rect {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        if x1 <= x0 || y1 <= y0 {
            return Rect(x: x0, y: y0, width: 0, height: 0)
        }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// 内側を `insets` の分だけ空けた矩形を返す。
    ///
    /// - Parameters:
    ///   - insets: 上下左右に空ける長さ。
    /// - Returns: `insets` の分だけ狭めた矩形。`insets` が大きすぎる場合は幅・高さが 0 になる。
    /// - Postcondition: `EdgeInsets` の各辺は負にならないため、矩形が広がることはない。
    public func inset(by insets: EdgeInsets) -> Rect {
        Rect(
            x: minX + insets.leading,
            y: minY + insets.top,
            width: max(0, width - insets.horizontal),
            height: max(0, height - insets.vertical)
        )
    }

    /// 四辺に同じ長さを空けた矩形を返す。
    ///
    /// - Parameters:
    ///   - amount: 各辺に空ける長さ（`Cell` の数で表す）。
    /// - Returns: `amount` の分だけ狭めた矩形。
    public func inset(by amount: Int) -> Rect {
        inset(by: EdgeInsets(all: amount))
    }
}

/// 上下左右に空ける長さ（`Cell` の数で表す）。負の値は 0 に丸められる。
public struct EdgeInsets: Hashable, Sendable {
    /// 上に空ける長さ。負の値は 0 に丸められる。
    public var top: Int {
        didSet { top = max(0, top) }
    }
    /// 左に空ける長さ。負の値は 0 に丸められる。
    public var leading: Int {
        didSet { leading = max(0, leading) }
    }
    /// 下に空ける長さ。負の値は 0 に丸められる。
    public var bottom: Int {
        didSet { bottom = max(0, bottom) }
    }
    /// 右に空ける長さ。負の値は 0 に丸められる。
    public var trailing: Int {
        didSet { trailing = max(0, trailing) }
    }

    /// 四辺に空ける長さを個別に指定して `EdgeInsets` を作る。
    ///
    /// - Parameters:
    ///   - top: 上に空ける長さ。
    ///   - leading: 左に空ける長さ。
    ///   - bottom: 下に空ける長さ。
    ///   - trailing: 右に空ける長さ。
    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = max(0, top)
        self.leading = max(0, leading)
        self.bottom = max(0, bottom)
        self.trailing = max(0, trailing)
    }

    /// 四辺に同じ長さを空ける `EdgeInsets` を作る。
    ///
    /// - Parameters:
    ///   - all: 各辺に空ける長さ。
    public init(all: Int) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    /// 左右と上下で空ける長さを分けた `EdgeInsets` を作る。
    ///
    /// - Parameters:
    ///   - horizontal: 左右に空ける長さ。
    ///   - vertical: 上下に空ける長さ。
    public init(horizontal: Int, vertical: Int) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    /// どの辺にも空けない `EdgeInsets`。
    public static let zero = EdgeInsets()

    /// 左右に空ける長さの合計。
    public var horizontal: Int { leading + trailing }
    /// 上下に空ける長さの合計。
    public var vertical: Int { top + bottom }
}

/// レイアウトの主軸。
public enum Axis: Hashable, Sendable {
    /// 横方向。
    case horizontal
    /// 縦方向。
    case vertical
}

/// 水平方向の揃え。
public enum HorizontalAlignment: Hashable, Sendable {
    /// 左端に寄せる。
    case leading
    /// 中央に置く。
    case center
    /// 右端に寄せる。
    case trailing
}

/// 垂直方向の揃え。
public enum VerticalAlignment: Hashable, Sendable {
    /// 上端に寄せる。
    case top
    /// 中央に置く。
    case center
    /// 下端に寄せる。
    case bottom
}

extension HorizontalAlignment {
    /// 幅 `available` の領域に幅 `content` を置くときの開始オフセット。
    ///
    /// - Parameters:
    ///   - content: 置く内容の幅。
    ///   - available: 使える領域の幅。
    /// - Returns: 領域の左端から数えたオフセット。内容が領域より広ければ 0。
    func offset(content: Int, available: Int) -> Int {
        switch self {
        case .leading: return 0
        case .center: return max(0, (available - content) / 2)
        case .trailing: return max(0, available - content)
        }
    }
}

extension VerticalAlignment {
    /// 高さ `available` の領域に高さ `content` を置くときの開始オフセット。
    ///
    /// - Parameters:
    ///   - content: 置く内容の高さ。
    ///   - available: 使える領域の高さ。
    /// - Returns: 領域の上端から数えたオフセット。内容が領域より高ければ 0。
    func offset(content: Int, available: Int) -> Int {
        switch self {
        case .top: return 0
        case .center: return max(0, (available - content) / 2)
        case .bottom: return max(0, available - content)
        }
    }
}
