/// レイアウト時に、余った領域をどれだけ引き取るかを表す。
///
/// 重みが 0 のビューは希望サイズのまま配置され、1 以上のビューが余白を重みに応じて分け合う。
public struct LayoutTraits: Hashable, Sendable {
    public var horizontalFlex: Int
    public var verticalFlex: Int

    public init(horizontalFlex: Int = 0, verticalFlex: Int = 0) {
        self.horizontalFlex = max(0, horizontalFlex)
        self.verticalFlex = max(0, verticalFlex)
    }

    /// 希望サイズのまま配置される。
    public static let fixed = LayoutTraits()
    /// 両方向に伸びる。
    public static let flexible = LayoutTraits(horizontalFlex: 1, verticalFlex: 1)

    public func flex(on axis: Axis) -> Int {
        switch axis {
        case .horizontal: return horizontalFlex
        case .vertical: return verticalFlex
        }
    }
}

/// 画面へ描画できるもの。
public protocol View {
    /// `proposal` の範囲で希望するサイズを返す。返す値は `proposal` を超えてもよいが、
    /// その場合はレイアウト側で切り詰められる。
    func sizeThatFits(_ proposal: Size) -> Size

    /// `rect` の領域へ描画する。`rect` の外へ描いてはならない。
    func render(into buffer: inout Buffer, rect: Rect)

    /// 余白の分配に関する性質。
    var layoutTraits: LayoutTraits { get }
}

extension View {
    public var layoutTraits: LayoutTraits { .fixed }
}

/// 何も描画しないビュー。
public struct EmptyView: View {
    public init() {}

    public func sizeThatFits(_ proposal: Size) -> Size { .zero }

    public func render(into buffer: inout Buffer, rect: Rect) {}
}

/// 領域全体を 1 文字で塗りつぶすビュー。
public struct Fill: View {
    public var character: Character
    public var style: Style

    public init(_ character: Character = " ", style: Style = .plain) {
        self.character = character
        self.style = style
    }

    public var layoutTraits: LayoutTraits { .flexible }

    public func sizeThatFits(_ proposal: Size) -> Size { proposal }

    public func render(into buffer: inout Buffer, rect: Rect) {
        buffer.fill(rect, with: Cell(character: character, style: style))
    }
}

/// 余白を押し広げるビュー。
public struct Spacer: View {
    /// 最低限確保する長さ。
    public var minLength: Int

    public init(minLength: Int = 0) {
        self.minLength = max(0, minLength)
    }

    public var layoutTraits: LayoutTraits { .flexible }

    public func sizeThatFits(_ proposal: Size) -> Size {
        Size(width: minLength, height: minLength)
    }

    public func render(into buffer: inout Buffer, rect: Rect) {}
}

/// 1 本の罫線。
public struct Divider: View {
    public var axis: Axis
    public var character: Character
    public var style: Style

    public init(axis: Axis = .horizontal, character: Character? = nil, style: Style = .plain) {
        self.axis = axis
        self.character = character ?? (axis == .horizontal ? "─" : "│")
        self.style = style
    }

    public var layoutTraits: LayoutTraits {
        switch axis {
        case .horizontal: return LayoutTraits(horizontalFlex: 1, verticalFlex: 0)
        case .vertical: return LayoutTraits(horizontalFlex: 0, verticalFlex: 1)
        }
    }

    public func sizeThatFits(_ proposal: Size) -> Size {
        switch axis {
        case .horizontal: return Size(width: proposal.width, height: 1)
        case .vertical: return Size(width: 1, height: proposal.height)
        }
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        buffer.fill(rect, with: Cell(character: character, style: style))
    }
}
