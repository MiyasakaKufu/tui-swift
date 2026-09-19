/// 端末上の座標。原点は左上、`x` は列、`y` は行を表す。
public struct Point: Hashable, Sendable {
    /// 列の位置。左端が 0。
    public var x: Int
    /// 行の位置。上端が 0。
    public var y: Int

    /// 座標を作る。
    ///
    /// - Parameters:
    ///   - x: 列の位置。
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
    ///   - dx: 列方向のずれ。
    ///   - dy: 行方向のずれ。
    /// - Returns: ずらした座標。
    public func offset(dx: Int = 0, dy: Int = 0) -> Point {
        Point(x: x + dx, y: y + dy)
    }
}

/// 桁数・行数で表したサイズ。負の値は 0 に丸められる。
public struct Size: Hashable, Sendable {
    /// 桁数。負の値は 0 に丸められる。
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
    ///   - width: 桁数。
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
    ///   - x: 左端の列。
    ///   - y: 上端の行。
    ///   - width: 桁数。
    ///   - height: 行数。
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    /// 原点にある、幅・高さが 0 の矩形。
    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    /// 桁数。
    public var width: Int { size.width }
    /// 行数。
    public var height: Int { size.height }
    /// 左端の列。
    public var minX: Int { origin.x }
    /// 上端の行。
    public var minY: Int { origin.y }
    /// 右端の列。この列は領域に含まれない。
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

    /// 内側に余白を取った矩形。
    ///
    /// - Parameters:
    ///   - insets: 上下左右に取る余白。
    /// - Returns: 余白の分だけ狭めた矩形。余白が大きすぎる場合は幅・高さが 0 になる。
    /// - Postcondition: 余白は負にならないため、矩形が広がることはない。
    public func inset(by insets: EdgeInsets) -> Rect {
        Rect(
            x: minX + insets.leading,
            y: minY + insets.top,
            width: max(0, width - insets.horizontal),
            height: max(0, height - insets.vertical)
        )
    }

    /// 四辺に同じ余白を取った矩形。
    ///
    /// - Parameters:
    ///   - amount: 各辺に取る余白。
    /// - Returns: 余白の分だけ狭めた矩形。
    public func inset(by amount: Int) -> Rect {
        inset(by: EdgeInsets(all: amount))
    }
}

/// 上下左右の余白。負の値は 0 に丸められる。
public struct EdgeInsets: Hashable, Sendable {
    /// 上の余白。負の値は 0 に丸められる。
    public var top: Int {
        didSet { top = max(0, top) }
    }
    /// 左の余白。負の値は 0 に丸められる。
    public var leading: Int {
        didSet { leading = max(0, leading) }
    }
    /// 下の余白。負の値は 0 に丸められる。
    public var bottom: Int {
        didSet { bottom = max(0, bottom) }
    }
    /// 右の余白。負の値は 0 に丸められる。
    public var trailing: Int {
        didSet { trailing = max(0, trailing) }
    }

    /// 四辺の余白を個別に指定して作る。
    ///
    /// - Parameters:
    ///   - top: 上の余白。
    ///   - leading: 左の余白。
    ///   - bottom: 下の余白。
    ///   - trailing: 右の余白。
    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = max(0, top)
        self.leading = max(0, leading)
        self.bottom = max(0, bottom)
        self.trailing = max(0, trailing)
    }

    /// 四辺に同じ余白を取る。
    ///
    /// - Parameters:
    ///   - all: 各辺の余白。
    public init(all: Int) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    /// 左右と上下で余白を分けて取る。
    ///
    /// - Parameters:
    ///   - horizontal: 左右の余白。
    ///   - vertical: 上下の余白。
    public init(horizontal: Int, vertical: Int) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    /// 余白なし。
    public static let zero = EdgeInsets()

    /// 左右の余白の合計。
    public var horizontal: Int { leading + trailing }
    /// 上下の余白の合計。
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
