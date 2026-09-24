/// スタックの主軸方向のサイズ配分。
@MainActor
enum StackLayout {

    /// 各子ビューに割り当てる主軸方向のサイズを求める。
    ///
    /// - Parameters:
    ///   - children: 並べる子ビュー。
    ///   - axis: 主軸の方向。
    ///   - available: 主軸方向に使える長さ。
    ///   - crossAvailable: 交差軸方向に使える長さ。
    ///   - spacing: 子ビューの間隔。
    ///   - context: 親が受け取った文脈。
    /// - Returns: `children` と同じ順序・同じ個数の、主軸方向のサイズ。
    /// - Postcondition: 間隔を含めた合計は `available` を超えない。
    static func mainAxisSizes(
        children: [any View],
        axis: Axis,
        available: Int,
        crossAvailable: Int,
        spacing: Int,
        context: RenderContext
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
        var sizes = children.enumerated().map { (index, child) -> Int in
            let isFlexible = child.layoutTraits.flex(on: axis) > 0
            let desired = context.sizeThatFits(
                of: child,
                index: index,
                proposal: isFlexible ? minimumProposal : proposal
            )
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
    ///
    /// - Parameters:
    ///   - extra: 配る長さ。
    ///   - sizes: 配り先のサイズ。重みを持つ要素だけが増える。
    ///   - children: `sizes` に対応する子ビュー。
    ///   - axis: 重みを読む軸。
    /// - Postcondition: 重みを持つ子が 1 つ以上あれば、`extra` をすべて配り切る。
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

        var leftover = extra - distributed
        var cursor = 0
        while leftover > 0 && !flexibleIndices.isEmpty {
            sizes[flexibleIndices[cursor % flexibleIndices.count]] += 1
            leftover -= 1
            cursor += 1
        }
    }

    /// 領域が足りない場合、後ろの子から削る。
    ///
    /// - Parameters:
    ///   - amount: 削る長さ。
    ///   - sizes: 削り先のサイズ。
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
public struct VStack: PrimitiveView {
    /// 並べる子ビュー。
    public var children: [any View]
    /// 子ビューの間隔。負の値は 0 に丸められる。
    public var spacing: Int
    /// 子ビューの水平方向の揃え。
    public var alignment: HorizontalAlignment

    /// 間隔と揃えを指定し、クロージャで子ビューを並べる。
    ///
    /// - Parameters:
    ///   - spacing: 子ビューの間隔。
    ///   - alignment: 子ビューの水平方向の揃え。
    ///   - content: 並べる子ビューを返すクロージャ。
    public init(
        spacing: Int = 0,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 子ビューの配列を直接渡して作る。
    ///
    /// - Parameters:
    ///   - children: 並べる子ビュー。
    ///   - spacing: 子ビューの間隔。
    ///   - alignment: 子ビューの水平方向の揃え。
    public init(children: [any View], spacing: Int = 0, alignment: HorizontalAlignment = .leading) {
        self.children = children
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 子ビューのうち最も大きい重み。
    public var layoutTraits: LayoutTraits {
        LayoutTraits(
            horizontalFlex: children.map { $0.layoutTraits.horizontalFlex }.max() ?? 0,
            verticalFlex: children.map { $0.layoutTraits.verticalFlex }.max() ?? 0
        )
    }

    /// 子ビューを縦に積んだときに必要なサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 間隔を含めた高さの合計と、最も広い子の幅から決まるサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        guard !children.isEmpty else { return .zero }
        var width = 0
        var height = spacing * (children.count - 1)
        var remaining = max(0, proposal.height - height)
        for (index, child) in children.enumerated() {
            let desired = context.sizeThatFits(
                of: child,
                index: index,
                proposal: Size(width: proposal.width, height: remaining)
            )
            width = max(width, desired.width)
            let used = min(desired.height, remaining)
            height += used
            remaining -= used
        }
        return Size(width: min(width, proposal.width), height: min(height, proposal.height))
    }

    /// 子ビューを縦に並べて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。はみ出す子ビューは描画されない。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        let sizes = StackLayout.mainAxisSizes(
            children: children,
            axis: .vertical,
            available: rect.height,
            crossAvailable: rect.width,
            spacing: spacing,
            context: context
        )

        var y = rect.minY
        for (index, child) in children.enumerated() {
            if y >= rect.maxY { break }
            let height = min(sizes[index], rect.maxY - y)
            if height > 0 {
                let desired = context.sizeThatFits(
                    of: child,
                    index: index,
                    proposal: Size(width: rect.width, height: height)
                )
                let width = child.layoutTraits.horizontalFlex > 0
                    ? rect.width
                    : min(desired.width, rect.width)
                let x = rect.minX + alignment.offset(content: width, available: rect.width)
                let childRect = Rect(x: x, y: y, width: width, height: height)
                context.render(child, index: index, into: &buffer, rect: childRect)
            }
            y += sizes[index] + spacing
        }
    }
}

/// 子ビューを横に並べる。
public struct HStack: PrimitiveView {
    /// 並べる子ビュー。
    public var children: [any View]
    /// 子ビューの間隔。負の値は 0 に丸められる。
    public var spacing: Int
    /// 子ビューの垂直方向の揃え。
    public var alignment: VerticalAlignment

    /// 間隔と揃えを指定し、クロージャで子ビューを並べる。
    ///
    /// - Parameters:
    ///   - spacing: 子ビューの間隔。
    ///   - alignment: 子ビューの垂直方向の揃え。
    ///   - content: 並べる子ビューを返すクロージャ。
    public init(
        spacing: Int = 0,
        alignment: VerticalAlignment = .top,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 子ビューの配列を直接渡して作る。
    ///
    /// - Parameters:
    ///   - children: 並べる子ビュー。
    ///   - spacing: 子ビューの間隔。
    ///   - alignment: 子ビューの垂直方向の揃え。
    public init(children: [any View], spacing: Int = 0, alignment: VerticalAlignment = .top) {
        self.children = children
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 子ビューのうち最も大きい重み。
    public var layoutTraits: LayoutTraits {
        LayoutTraits(
            horizontalFlex: children.map { $0.layoutTraits.horizontalFlex }.max() ?? 0,
            verticalFlex: children.map { $0.layoutTraits.verticalFlex }.max() ?? 0
        )
    }

    /// 子ビューを横に積んだときに必要なサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 間隔を含めた幅の合計と、最も高い子の高さから決まるサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        guard !children.isEmpty else { return .zero }
        var height = 0
        var width = spacing * (children.count - 1)
        var remaining = max(0, proposal.width - width)
        for (index, child) in children.enumerated() {
            let desired = context.sizeThatFits(
                of: child,
                index: index,
                proposal: Size(width: remaining, height: proposal.height)
            )
            height = max(height, desired.height)
            let used = min(desired.width, remaining)
            width += used
            remaining -= used
        }
        return Size(width: min(width, proposal.width), height: min(height, proposal.height))
    }

    /// 子ビューを横に並べて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。はみ出す子ビューは描画されない。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        let sizes = StackLayout.mainAxisSizes(
            children: children,
            axis: .horizontal,
            available: rect.width,
            crossAvailable: rect.height,
            spacing: spacing,
            context: context
        )

        var x = rect.minX
        for (index, child) in children.enumerated() {
            if x >= rect.maxX { break }
            let width = min(sizes[index], rect.maxX - x)
            if width > 0 {
                let desired = context.sizeThatFits(
                    of: child,
                    index: index,
                    proposal: Size(width: width, height: rect.height)
                )
                let height = child.layoutTraits.verticalFlex > 0
                    ? rect.height
                    : min(desired.height, rect.height)
                let y = rect.minY + alignment.offset(content: height, available: rect.height)
                let childRect = Rect(x: x, y: y, width: width, height: height)
                context.render(child, index: index, into: &buffer, rect: childRect)
            }
            x += sizes[index] + spacing
        }
    }
}
