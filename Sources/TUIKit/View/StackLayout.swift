/// スタックの主軸方向のサイズ配分。
enum StackLayout {

    /// 各子ビューに割り当てる主軸方向のサイズを求める。
    static func mainAxisSizes(
        children: [any View],
        axis: Axis,
        available: Int,
        crossAvailable: Int,
        spacing: Int
    ) -> [Int] {
        guard !children.isEmpty else { return [] }

        let totalSpacing = spacing * (children.count - 1)
        let content = max(0, available - totalSpacing)

        let proposal: Size
        let minimumProposal: Size
        switch axis {
        case .vertical:
            proposal = Size(width: crossAvailable, height: content)
            minimumProposal = Size(width: crossAvailable, height: 0)
        case .horizontal:
            proposal = Size(width: content, height: crossAvailable)
            minimumProposal = Size(width: 0, height: crossAvailable)
        }

        // 伸びるビューには主軸 0 を提案し、最小サイズだけを先に確保する。
        // 余りは後から重みに応じて配るので、先着順に領域を食い尽くすことがない。
        var sizes = children.map { child -> Int in
            let isFlexible = child.layoutTraits.flex(on: axis) > 0
            let desired = child.sizeThatFits(isFlexible ? minimumProposal : proposal)
            let value = (axis == .vertical) ? desired.height : desired.width
            return max(0, min(value, content))
        }

        let total = sizes.reduce(0, +)
        if total < content {
            distribute(extra: content - total, to: &sizes, children: children, axis: axis)
        } else if total > content {
            shrink(by: total - content, sizes: &sizes)
        }
        return sizes
    }

    /// 余った領域を flex の重みに応じて配る。
    private static func distribute(extra: Int, to sizes: inout [Int], children: [any View], axis: Axis) {
        let weights = children.map { $0.layoutTraits.flex(on: axis) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return }

        var distributed = 0
        var flexibleIndices: [Int] = []
        for index in sizes.indices where weights[index] > 0 {
            flexibleIndices.append(index)
            let share = extra * weights[index] / totalWeight
            sizes[index] += share
            distributed += share
        }

        // 整数除算で配りきれなかった分を先頭から 1 ずつ足す。
        var leftover = extra - distributed
        var cursor = 0
        while leftover > 0 && !flexibleIndices.isEmpty {
            sizes[flexibleIndices[cursor % flexibleIndices.count]] += 1
            leftover -= 1
            cursor += 1
        }
    }

    /// 領域が足りない場合、後ろの子から削る。
    private static func shrink(by amount: Int, sizes: inout [Int]) {
        var excess = amount
        var index = sizes.count - 1
        while excess > 0 && index >= 0 {
            let reduction = min(excess, sizes[index])
            sizes[index] -= reduction
            excess -= reduction
            index -= 1
        }
    }
}

/// 子ビューを縦に並べる。
public struct VStack: View {
    public var children: [any View]
    public var spacing: Int
    public var alignment: HorizontalAlignment

    public init(
        spacing: Int = 0,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    public init(children: [any View], spacing: Int = 0, alignment: HorizontalAlignment = .leading) {
        self.children = children
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    public var layoutTraits: LayoutTraits {
        LayoutTraits(
            horizontalFlex: children.map { $0.layoutTraits.horizontalFlex }.max() ?? 0,
            verticalFlex: children.map { $0.layoutTraits.verticalFlex }.max() ?? 0
        )
    }

    public func sizeThatFits(_ proposal: Size) -> Size {
        guard !children.isEmpty else { return .zero }
        var width = 0
        var height = spacing * (children.count - 1)
        var remaining = max(0, proposal.height - height)
        for child in children {
            let desired = child.sizeThatFits(Size(width: proposal.width, height: remaining))
            width = max(width, desired.width)
            let used = min(desired.height, remaining)
            height += used
            remaining -= used
        }
        return Size(width: min(width, proposal.width), height: min(height, proposal.height))
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }
        let sizes = StackLayout.mainAxisSizes(
            children: children,
            axis: .vertical,
            available: rect.height,
            crossAvailable: rect.width,
            spacing: spacing
        )

        var y = rect.minY
        for (index, child) in children.enumerated() {
            if y >= rect.maxY { break }
            let height = min(sizes[index], rect.maxY - y)
            if height > 0 {
                let desired = child.sizeThatFits(Size(width: rect.width, height: height))
                let width = child.layoutTraits.horizontalFlex > 0
                    ? rect.width
                    : min(desired.width, rect.width)
                let x = rect.minX + alignment.offset(content: width, available: rect.width)
                child.render(into: &buffer, rect: Rect(x: x, y: y, width: width, height: height))
            }
            y += sizes[index] + spacing
        }
    }
}

/// 子ビューを横に並べる。
public struct HStack: View {
    public var children: [any View]
    public var spacing: Int
    public var alignment: VerticalAlignment

    public init(
        spacing: Int = 0,
        alignment: VerticalAlignment = .top,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    public init(children: [any View], spacing: Int = 0, alignment: VerticalAlignment = .top) {
        self.children = children
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    public var layoutTraits: LayoutTraits {
        LayoutTraits(
            horizontalFlex: children.map { $0.layoutTraits.horizontalFlex }.max() ?? 0,
            verticalFlex: children.map { $0.layoutTraits.verticalFlex }.max() ?? 0
        )
    }

    public func sizeThatFits(_ proposal: Size) -> Size {
        guard !children.isEmpty else { return .zero }
        var height = 0
        var width = spacing * (children.count - 1)
        var remaining = max(0, proposal.width - width)
        for child in children {
            let desired = child.sizeThatFits(Size(width: remaining, height: proposal.height))
            height = max(height, desired.height)
            let used = min(desired.width, remaining)
            width += used
            remaining -= used
        }
        return Size(width: min(width, proposal.width), height: min(height, proposal.height))
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }
        let sizes = StackLayout.mainAxisSizes(
            children: children,
            axis: .horizontal,
            available: rect.width,
            crossAvailable: rect.height,
            spacing: spacing
        )

        var x = rect.minX
        for (index, child) in children.enumerated() {
            if x >= rect.maxX { break }
            let width = min(sizes[index], rect.maxX - x)
            if width > 0 {
                let desired = child.sizeThatFits(Size(width: width, height: rect.height))
                let height = child.layoutTraits.verticalFlex > 0
                    ? rect.height
                    : min(desired.height, rect.height)
                let y = rect.minY + alignment.offset(content: height, available: rect.height)
                child.render(into: &buffer, rect: Rect(x: x, y: y, width: width, height: height))
            }
            x += sizes[index] + spacing
        }
    }
}
