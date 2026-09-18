/// 端末上の座標。原点は左上、`x` は列、`y` は行を表す。
public struct Point: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(x: 0, y: 0)

    public func offset(dx: Int = 0, dy: Int = 0) -> Point {
        Point(x: x + dx, y: y + dy)
    }
}

/// 桁数・行数で表したサイズ。負の値は 0 に丸められる。
public struct Size: Hashable, Sendable {
    public var width: Int {
        didSet { width = max(0, width) }
    }
    public var height: Int {
        didSet { height = max(0, height) }
    }

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public static let zero = Size(width: 0, height: 0)

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// 各辺を `other` 以下に切り詰めたサイズ。
    public func clamped(to other: Size) -> Size {
        Size(width: min(width, other.width), height: min(height, other.height))
    }
}

/// 矩形領域。`maxX` / `maxY` は排他的（領域に含まれない）。
public struct Rect: Hashable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    public var width: Int { size.width }
    public var height: Int { size.height }
    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width }
    public var maxY: Int { origin.y + size.height }
    public var isEmpty: Bool { size.isEmpty }

    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// 共通部分。重なりがない場合は幅・高さ 0 の矩形を返す。
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

    /// 内側に余白を取った矩形。余白は負にならないため、矩形が広がることはない。
    /// 余白が大きすぎる場合は幅・高さが 0 になる。
    public func inset(by insets: EdgeInsets) -> Rect {
        Rect(
            x: minX + insets.leading,
            y: minY + insets.top,
            width: max(0, width - insets.horizontal),
            height: max(0, height - insets.vertical)
        )
    }

    public func inset(by amount: Int) -> Rect {
        inset(by: EdgeInsets(all: amount))
    }
}

/// 上下左右の余白。負の値は 0 に丸められる。
public struct EdgeInsets: Hashable, Sendable {
    public var top: Int {
        didSet { top = max(0, top) }
    }
    public var leading: Int {
        didSet { leading = max(0, leading) }
    }
    public var bottom: Int {
        didSet { bottom = max(0, bottom) }
    }
    public var trailing: Int {
        didSet { trailing = max(0, trailing) }
    }

    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = max(0, top)
        self.leading = max(0, leading)
        self.bottom = max(0, bottom)
        self.trailing = max(0, trailing)
    }

    public init(all: Int) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    public init(horizontal: Int, vertical: Int) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    public static let zero = EdgeInsets()

    public var horizontal: Int { leading + trailing }
    public var vertical: Int { top + bottom }
}

/// レイアウトの主軸。
public enum Axis: Hashable, Sendable {
    case horizontal
    case vertical
}

/// 水平方向の揃え。
public enum HorizontalAlignment: Hashable, Sendable {
    case leading
    case center
    case trailing
}

/// 垂直方向の揃え。
public enum VerticalAlignment: Hashable, Sendable {
    case top
    case center
    case bottom
}

extension HorizontalAlignment {
    /// 幅 `available` の領域に幅 `content` を置くときの開始オフセット。
    func offset(content: Int, available: Int) -> Int {
        switch self {
        case .leading: return 0
        case .center: return max(0, (available - content) / 2)
        case .trailing: return max(0, available - content)
        }
    }
}

extension VerticalAlignment {
    func offset(content: Int, available: Int) -> Int {
        switch self {
        case .top: return 0
        case .center: return max(0, (available - content) / 2)
        case .bottom: return max(0, available - content)
        }
    }
}
