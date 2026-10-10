/// `VStack`・`HStack` の主軸方向のサイズ配分。
@MainActor
enum StackLayout {

    /// 中の `View` それぞれに割り当てる主軸方向のサイズを求める。
    ///
    /// - Parameters:
    ///   - children: 並べる `View`。
    ///   - axis: 主軸の方向。
    ///   - available: 主軸方向に使える長さ。
    ///   - crossAvailable: 交差軸方向に使える長さ。
    ///   - spacing: 中の `View` の間隔。
    ///   - context: `VStack`・`HStack` が `context` 引数で受け取った `RenderContext`。
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

        // `LayoutTraits.flex(on:)` の値が 1 以上の `View` にも `proposal` を渡してはいけない。`proposal` の主軸方向の
        // 長さをそのまま返す `View`（`HStack` の中の `TextField` など）が `content` を使い切り、後ろの `View` は
        // `shrink(by:sizes:)` で 0 まで削られる。
        var sizes = children.enumerated().map { (index, child) -> Int in
            let isFlexible = context.layoutTraits(of: child, index: index).flex(on: axis) > 0
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
            distribute(extra: content - total, to: &sizes, children: children, axis: axis, context: context)
        } else if total > content {
            shrink(by: total - content, sizes: &sizes)
        }
        return sizes
    }

    /// `VStack`・`HStack` が配ったあとに残る `Size` の主軸方向の長さを、`LayoutTraits.flex(on:)` の値に応じて配る。
    ///
    /// - Parameters:
    ///   - extra: 配る長さ。
    ///   - sizes: 配り先のサイズ。`LayoutTraits.flex(on:)` の値が 1 以上の `View` の分だけが増える。
    ///   - children: `sizes` に対応する、中の `View`。
    ///   - axis: `LayoutTraits.flex(on:)` に渡す軸。
    ///   - context: `VStack`・`HStack` が `context` 引数で受け取った `RenderContext`。
    /// - Postcondition: `LayoutTraits.flex(on:)` の値が 1 以上の `View` が 1 つ以上あれば、`extra` をすべて配り切る。
    private static func distribute(
        extra: Int,
        to sizes: inout [Int],
        children: [any View],
        axis: Axis,
        context: RenderContext
    ) {
        let weights = children.enumerated().map { context.layoutTraits(of: $1, index: $0).flex(on: axis) }
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

    /// 領域が足りない場合、後ろの `View` の分から削る。
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

/// 中の `View` を縦に並べる `View`。
public struct VStack: PrimitiveView {
    /// 並べる `View`。
    public var children: [any View]
    /// 中の `View` の間隔。負の値は 0 に丸められる。
    public var spacing: Int
    /// 中の `View` の水平方向の揃え。
    public var alignment: HorizontalAlignment

    /// 間隔と揃えと、中の `View` を返すクロージャから `VStack` を作る。
    ///
    /// - Parameters:
    ///   - spacing: 中の `View` の間隔。
    ///   - alignment: 中の `View` の水平方向の揃え。
    ///   - content: 並べる `View` を返すクロージャ。
    public init(
        spacing: Int = 0,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 中の `View` の配列と、間隔と揃えから `VStack` を作る。
    ///
    /// - Parameters:
    ///   - children: 並べる `View`。
    ///   - spacing: 中の `View` の間隔。
    ///   - alignment: 中の `View` の水平方向の揃え。
    public init(children: [any View], spacing: Int = 0, alignment: HorizontalAlignment = .leading) {
        self.children = children
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 中の `View` の `LayoutTraits` を、方向ごとに最大をとって返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` のそれぞれに、中の `View` での最大をとった
    ///   `LayoutTraits`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        let traits = children.enumerated().map { context.layoutTraits(of: $1, index: $0) }
        return LayoutTraits(
            horizontalFlex: traits.map(\.horizontalFlex).max() ?? 0,
            verticalFlex: traits.map(\.verticalFlex).max() ?? 0
        )
    }

    /// 中の `View` を縦に積んだときのサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 間隔を含めた高さの合計と、中の `View` のうち最も広いものの幅から決まるサイズ。
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

    /// 中の `View` を縦に並べて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。はみ出す `View` は描画されない。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
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
                let width = context.layoutTraits(of: child, index: index).horizontalFlex > 0
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

/// 中の `View` を横に並べる `View`。
public struct HStack: PrimitiveView {
    /// 並べる `View`。
    public var children: [any View]
    /// 中の `View` の間隔。負の値は 0 に丸められる。
    public var spacing: Int
    /// 中の `View` の垂直方向の揃え。
    public var alignment: VerticalAlignment

    /// 間隔と揃えと、中の `View` を返すクロージャから `HStack` を作る。
    ///
    /// - Parameters:
    ///   - spacing: 中の `View` の間隔。
    ///   - alignment: 中の `View` の垂直方向の揃え。
    ///   - content: 並べる `View` を返すクロージャ。
    public init(
        spacing: Int = 0,
        alignment: VerticalAlignment = .top,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 中の `View` の配列と、間隔と揃えから `HStack` を作る。
    ///
    /// - Parameters:
    ///   - children: 並べる `View`。
    ///   - spacing: 中の `View` の間隔。
    ///   - alignment: 中の `View` の垂直方向の揃え。
    public init(children: [any View], spacing: Int = 0, alignment: VerticalAlignment = .top) {
        self.children = children
        self.spacing = max(0, spacing)
        self.alignment = alignment
    }

    /// 中の `View` の `LayoutTraits` を、方向ごとに最大をとって返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` のそれぞれに、中の `View` での最大をとった
    ///   `LayoutTraits`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        let traits = children.enumerated().map { context.layoutTraits(of: $1, index: $0) }
        return LayoutTraits(
            horizontalFlex: traits.map(\.horizontalFlex).max() ?? 0,
            verticalFlex: traits.map(\.verticalFlex).max() ?? 0
        )
    }

    /// 中の `View` を横に積んだときのサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 間隔を含めた幅の合計と、中の `View` のうち最も高いものの高さから決まるサイズ。
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

    /// 中の `View` を横に並べて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。はみ出す `View` は描画されない。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
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
                let height = context.layoutTraits(of: child, index: index).verticalFlex > 0
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
