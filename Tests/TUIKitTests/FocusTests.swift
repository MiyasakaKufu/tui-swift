import XCTest
@testable import TUIKit

final class FocusTests: XCTestCase {

    // MARK: - 補助

    /// 1 フレーム分の描画を回し、矩形を登録させる。
    ///
    /// - Parameters:
    ///   - view: 描画するビュー。
    ///   - manager: 登録先。
    ///   - size: 画面の大きさ。
    private func renderFrame(_ view: any View, into manager: FocusManager, size: Size) {
        var buffer = Buffer(size: size)
        manager.beginFrame()
        view.render(into: &buffer, rect: buffer.bounds)
        manager.endFrame()
    }

    /// 矩形だけを決めて、描画なしに 1 フレーム分を登録する。
    ///
    /// - Parameters:
    ///   - entries: 登録する対象と、その矩形。並びが描画順になる。
    ///   - manager: 登録先。
    private func registerFrame(_ entries: [(FocusTarget, Rect)], into manager: FocusManager) {
        manager.beginFrame()
        for (target, rect) in entries {
            manager.register(target, rect: rect)
        }
        manager.endFrame()
    }

    /// 重ならない位置に並べた 3 つの対象を登録する。
    ///
    /// - Parameters:
    ///   - manager: 登録先。
    /// - Returns: 描画順に並べた対象。
    private func registerThreeTargets(into manager: FocusManager) -> [RecordingTarget] {
        let targets = [RecordingTarget(), RecordingTarget(), RecordingTarget()]
        var entries: [(FocusTarget, Rect)] = []
        for (offset, target) in targets.enumerated() {
            entries.append((target, Rect(x: 0, y: offset, width: 10, height: 1)))
        }
        registerFrame(entries, into: manager)
        return targets
    }

    // MARK: - フォーカスの保持

    func testFirstTargetIsFocusedAfterFirstFrame() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        XCTAssertTrue(manager.isFocused(targets[0]))
    }

    func testAutomaticFocusCanBeDisabled() {
        let manager = FocusManager()
        manager.focusesFirstAutomatically = false
        _ = registerThreeTargets(into: manager)
        XCTAssertNil(manager.focusedTarget)
    }

    func testFocusCanBeSetDirectly() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        manager.focus(targets[2])
        XCTAssertTrue(manager.isFocused(targets[2]))
        XCTAssertFalse(manager.isFocused(targets[0]))
    }

    func testTargetMissingFromFrameLosesFocus() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        manager.focus(targets[2])

        registerFrame([(targets[0], Rect(x: 0, y: 0, width: 10, height: 1))], into: manager)
        XCTAssertTrue(manager.isFocused(targets[0]), "消えたウィジェットにフォーカスが残っている")
    }

    func testRegisteringSameTargetTwiceLeavesOneStop() {
        let manager = FocusManager()
        let first = RecordingTarget()
        let second = RecordingTarget()
        registerFrame(
            [
                (first, Rect(x: 0, y: 0, width: 4, height: 1)),
                (second, Rect(x: 0, y: 1, width: 4, height: 1)),
                (first, Rect(x: 0, y: 2, width: 4, height: 1)),
            ],
            into: manager
        )

        XCTAssertTrue(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(second))
        XCTAssertTrue(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(first), "同じ対象が 2 回巡っている")
        let press = MouseEvent(position: Point(x: 1, y: 2), button: .left, action: .press)
        XCTAssertTrue(manager.handle(.mouse(press)), "当たり判定が後から登録した矩形になっていない")
        XCTAssertTrue(manager.isFocused(first))
    }

    // MARK: - Tab による移動

    func testTabMovesFocusInRenderOrder() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)

        XCTAssertTrue(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(targets[1]))
        XCTAssertTrue(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(targets[2]))
    }

    func testShiftTabMovesFocusBackward() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        manager.focus(targets[2])

        XCTAssertTrue(manager.handle(.key(KeyEvent(.backTab))))
        XCTAssertTrue(manager.isFocused(targets[1]))
        XCTAssertTrue(manager.handle(.key(KeyEvent(.backTab))))
        XCTAssertTrue(manager.isFocused(targets[0]))
    }

    func testFocusWrapsAroundAtBothEnds() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)

        XCTAssertTrue(manager.handle(.key(KeyEvent(.backTab))))
        XCTAssertTrue(manager.isFocused(targets[2]))
        XCTAssertTrue(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(targets[0]))
    }

    func testFocusStopsAtEndsWhenWrappingIsDisabled() {
        let manager = FocusManager()
        manager.wrapsAround = false
        let targets = registerThreeTargets(into: manager)

        XCTAssertFalse(manager.handle(.key(KeyEvent(.backTab))))
        XCTAssertTrue(manager.isFocused(targets[0]))

        manager.focus(targets[2])
        XCTAssertFalse(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(targets[2]))
    }

    func testTabIsNotConsumedWithoutTargets() {
        let manager = FocusManager()
        XCTAssertFalse(manager.handle(.key(KeyEvent(.tab))))
    }

    // MARK: - キーの配送

    func testKeyIsDeliveredOnlyToFocusedTarget() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)

        XCTAssertTrue(manager.handle(.key(KeyEvent(.up))))
        XCTAssertEqual(targets[0].received, [.key(KeyEvent(.up))])
        XCTAssertEqual(targets[1].received, [])
        XCTAssertEqual(targets[2].received, [])
    }

    func testUnhandledKeyIsNotConsumed() {
        let manager = FocusManager()
        let target = RecordingTarget(handlesEvents: false)
        registerFrame([(target, Rect(x: 0, y: 0, width: 4, height: 1))], into: manager)

        XCTAssertFalse(manager.handle(.key(KeyEvent(.character("q")))), "ルートへ渡らない")
        XCTAssertEqual(target.received, [.key(KeyEvent(.character("q")))])
    }

    func testPasteIsDeliveredToFocusedTarget() {
        let manager = FocusManager()
        let target = RecordingTarget()
        registerFrame([(target, Rect(x: 0, y: 0, width: 4, height: 1))], into: manager)

        XCTAssertTrue(manager.handle(.paste("貼り付け")))
        XCTAssertEqual(target.received, [.paste("貼り付け")])
    }

    func testApplicationWideEventsAreNotDelivered() {
        let manager = FocusManager()
        let target = RecordingTarget()
        registerFrame([(target, Rect(x: 0, y: 0, width: 4, height: 1))], into: manager)

        XCTAssertFalse(manager.handle(.resize(Size(width: 8, height: 2))))
        XCTAssertFalse(manager.handle(.focus(true)))
        XCTAssertEqual(target.received, [])
    }

    func testCursorPositionComesFromFocusedTarget() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        targets[1].cursorPosition = Point(x: 3, y: 1)

        XCTAssertNil(manager.cursorPosition)
        manager.focus(targets[1])
        XCTAssertEqual(manager.cursorPosition, Point(x: 3, y: 1))
    }

    // MARK: - マウスの配送

    func testPressFocusesTargetUnderPointer() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        let press = MouseEvent(position: Point(x: 2, y: 2), button: .left, action: .press)

        XCTAssertTrue(manager.handle(.mouse(press)))
        XCTAssertTrue(manager.isFocused(targets[2]))
        XCTAssertEqual(targets[2].received, [.mouse(press)])
        XCTAssertEqual(targets[0].received, [])
    }

    func testFrontMostTargetTakesMouseAndBlocksTheOneBelow() {
        let manager = FocusManager()
        let below = RecordingTarget()
        let above = RecordingTarget()
        registerFrame(
            [
                (below, Rect(x: 0, y: 0, width: 10, height: 10)),
                (above, Rect(x: 2, y: 2, width: 4, height: 4)),
            ],
            into: manager
        )
        let press = MouseEvent(position: Point(x: 3, y: 3), button: .left, action: .press)

        XCTAssertTrue(manager.handle(.mouse(press)))
        XCTAssertTrue(manager.isFocused(above))
        XCTAssertEqual(above.received, [.mouse(press)])
        XCTAssertEqual(below.received, [], "手前のウィジェットを抜けて下へ届いている")
    }

    func testWheelDoesNotMoveFocus() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        let wheel = MouseEvent(position: Point(x: 2, y: 2), button: .none, action: .scrollDown)

        XCTAssertTrue(manager.handle(.mouse(wheel)))
        XCTAssertEqual(targets[2].received, [.mouse(wheel)], "位置の下のウィジェットへ届いていない")
        XCTAssertTrue(manager.isFocused(targets[0]), "ホイールでフォーカスが動いている")
    }

    func testMouseOutsideEveryTargetIsNotConsumed() {
        let manager = FocusManager()
        let targets = registerThreeTargets(into: manager)
        let press = MouseEvent(position: Point(x: 20, y: 20), button: .left, action: .press)

        XCTAssertFalse(manager.handle(.mouse(press)))
        XCTAssertTrue(manager.isFocused(targets[0]))
        XCTAssertEqual(targets[0].received, [])
    }

    // MARK: - 描画による登録

    func testFocusableViewRegistersRenderedRect() {
        let manager = FocusManager()
        let top = RecordingTarget()
        let bottom = RecordingTarget()
        let view = VStack(spacing: 0) {
            Fill("a").focusable(top, in: manager)
            Fill("b").focusable(bottom, in: manager)
        }

        renderFrame(view, into: manager, size: Size(width: 4, height: 4))

        XCTAssertTrue(manager.isFocused(top), "描画順の先頭がフォーカスされていない")
        XCTAssertTrue(
            manager.handle(.mouse(MouseEvent(position: Point(x: 1, y: 3), button: .left, action: .press)))
        )
        XCTAssertTrue(manager.isFocused(bottom))
    }

    func testFocusableViewRegistersTheRectItWraps() {
        let manager = FocusManager()
        let target = RecordingTarget()
        let view = Text("あ").border().focusable(target, in: manager)

        renderFrame(view, into: manager, size: Size(width: 6, height: 3))

        let borderCorner = Point(x: 0, y: 0)
        let press = MouseEvent(position: borderCorner, button: .left, action: .press)
        XCTAssertTrue(manager.handle(.mouse(press)), "枠線の上のクリックが届いていない")
        XCTAssertEqual(target.received, [.mouse(press)])
    }

    func testRegistrationIsIgnoredOutsideDrawing() {
        let manager = FocusManager()
        let target = RecordingTarget()
        manager.register(target, rect: Rect(x: 0, y: 0, width: 4, height: 1))

        XCTAssertNil(manager.focusedTarget)
        XCTAssertFalse(manager.handle(.key(KeyEvent(.tab))))
    }

    // MARK: - ウィジェットとの組み合わせ

    func testWidgetStatesWorkAsFocusTargets() {
        let manager = FocusManager()
        let list = ListState()
        let field = TextFieldState()
        let view = VStack(spacing: 0) {
            ListView(items: ["一", "二", "三"], state: list).focusable(list, in: manager)
            TextField(state: field).focusable(field, in: manager)
        }

        renderFrame(view, into: manager, size: Size(width: 8, height: 4))

        XCTAssertTrue(manager.isFocused(list))
        XCTAssertTrue(manager.handle(.key(KeyEvent(.down))))
        XCTAssertEqual(list.selectedIndex, 1)

        XCTAssertTrue(manager.handle(.key(KeyEvent(.tab))))
        XCTAssertTrue(manager.isFocused(field))
        XCTAssertTrue(manager.handle(.key(KeyEvent(.character("あ")))))
        XCTAssertEqual(field.text, "あ")
        XCTAssertEqual(list.selectedIndex, 1, "フォーカスの外れたリストへキーが届いている")

        XCTAssertEqual(manager.cursorPosition, field.renderedCursorPoint)
        XCTAssertFalse(manager.handle(.key(KeyEvent(.escape))), "未処理のキーがルートへ渡らない")
    }
}

// MARK: - テスト用のフォーカス対象

/// 配送されたイベントを記録するフォーカス対象。
private final class RecordingTarget: FocusTarget {

    /// 配送されたイベントを届いた順に並べたもの。
    private(set) var received: [InputEvent] = []
    /// `handle(_:)` が返す値。
    var handlesEvents: Bool
    /// 端末カーソルを置きたい位置。
    var cursorPosition: Point?

    /// イベントを処理するかを決めて作る。
    ///
    /// - Parameters:
    ///   - handlesEvents: `handle(_:)` が返す値。
    init(handlesEvents: Bool = true) {
        self.handlesEvents = handlesEvents
    }

    /// イベントを記録する。
    ///
    /// - Parameters:
    ///   - event: 配送されたイベント。
    /// - Returns: `handlesEvents` の値。
    func handle(_ event: InputEvent) -> Bool {
        received.append(event)
        return handlesEvents
    }
}
