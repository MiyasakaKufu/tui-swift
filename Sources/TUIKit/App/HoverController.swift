/// `MouseEvent` が届くたびにマウスポインタが上にある ``View`` を決め、変わったら ``View/onHover(perform:)`` のクロージャを呼び出すクラス。
///
/// マウスポインタが上にある ``View`` は、直前の描画で ``View`` が ``Buffer`` へ書き込んだ矩形から、``InputEvent`` の `.mouse` を当てるのと同じ規則で決める。
@MainActor
final class HoverController {
    /// `false` なら、``View/onHover(perform:)`` のクロージャを呼び出さない。
    var isEnabled = true

    /// 直前にたどった ``View/onHover(perform:)``。たどった順に並ぶ。
    private var handlers: [HoverHandler] = []

    /// 直前にたどった ``View`` の一覧から作った `FocusIndex`。
    private var index = FocusIndex()

    /// マウスポインタが上にあるとして `true` を渡し、まだ `false` を渡していない ``View/onHover(perform:)``。最後に決め直したときのたどった順に並ぶ。
    private var hovered: [HoverHandler] = []

    /// `HoverController` を作る。
    init() {}

    /// たどった ``View`` の一覧から、``View/onHover(perform:)`` を集め直す。
    ///
    /// - Parameters:
    ///   - visited: 描画より前にたどった順に並べた `VisitedView`。
    ///   - index: `visited` から作った `FocusIndex`。マウスポインタの位置の ``View`` へ ``InputEvent`` を渡してよいかを調べるのに使う。
    func collect(_ visited: [ViewGraph.VisitedView], index: FocusIndex) {
        self.index = index
        handlers = visited.compactMap { visitedView in
            guard let view = visitedView.view as? any HoverHandlingView else { return nil }
            return HoverHandler(nodeID: visitedView.node.id, path: visitedView.node.path, action: view.hoverAction)
        }
    }

    /// `point` でマウスポインタが上にある ``View`` を決め直し、変わった ``View`` の ``View/onHover(perform:)`` のクロージャを呼び出す。
    ///
    /// - Parameters:
    ///   - point: 届いた `MouseEvent` の位置。
    ///   - hitRegions: 直前の描画で ``View`` が ``Buffer`` へ書き込んだ矩形。書き込んだ順に並ぶ。
    /// - Postcondition: 上から外れた ``View`` へ `false` を、内側のものから順に渡してから、上に来た ``View`` へ `true` を、外側のものから順に渡している。直前にたどられなかった ``View`` は、上から外れたものとする。`point` でいちばん手前に書き込んだ ``View`` が `FocusIndex.acceptsInput(at:)` で `false` になるなら、どの ``View`` も上から外れたものとする。
    func movePointer(to point: Point, hitRegions: [HitRegion]) {
        guard isEnabled else { return }
        let next = hoveredHandlers(at: point, in: hitRegions)
        let nextIDs = Set(next.map(\.nodeID))
        let previousIDs = Set(hovered.map(\.nodeID))
        let exited = hovered.filter { !nextIDs.contains($0.nodeID) }
        let entered = next.filter { !previousIDs.contains($0.nodeID) }
        hovered = next

        for handler in exited.reversed() { handler.action(false) }
        for handler in entered { handler.action(true) }
    }

    /// `point` でいちばん手前に ``Buffer`` へ書き込んだ ``View`` を内側に含む ``View/onHover(perform:)`` を返す。
    ///
    /// - Parameters:
    ///   - point: マウスポインタの位置。
    ///   - hitRegions: 直前の描画で ``View`` が ``Buffer`` へ書き込んだ矩形。書き込んだ順に並ぶ。
    /// - Returns: マウスポインタが上にある ``View/onHover(perform:)``。たどった順に並ぶ。いちばん手前に書き込んだ ``View`` が `FocusIndex.acceptsInput(at:)` で `false` になるなら空。
    private func hoveredHandlers(at point: Point, in hitRegions: [HitRegion]) -> [HoverHandler] {
        guard let region = hitRegions.last(where: { $0.rect.contains(point) }),
              index.acceptsInput(at: region.path)
        else { return [] }
        return handlers.filter { $0.path.contains(region.path) }
    }
}

/// ``View/onHover(perform:)`` 1 つ分。
@MainActor
struct HoverHandler {
    /// ``View/onHover(perform:)`` の戻り値の ``View`` の `ViewNode.id`。
    let nodeID: Int
    /// ``View/onHover(perform:)`` の戻り値の ``View`` の `ViewPath`。
    let path: ViewPath
    /// ``View/onHover(perform:)`` に渡されたクロージャ。
    let action: @MainActor (Bool) -> Void
}
