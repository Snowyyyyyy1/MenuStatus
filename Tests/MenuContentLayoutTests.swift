import XCTest
@testable import MenuStatus

final class MenuContentLayoutTests: XCTestCase {
    func testUnmeasuredContentDefaultsToScroll() {
        XCTAssertTrue(MenuContentLayout.needsScroll(measuredHeight: nil, maxVisibleContentHeight: 480))
        XCTAssertEqual(
            MenuContentLayout.scrollFrameHeight(measuredHeight: nil, maxVisibleContentHeight: 480),
            480
        )
    }

    func testShortContentShrinksToMeasuredHeight() {
        XCTAssertFalse(MenuContentLayout.needsScroll(measuredHeight: 240, maxVisibleContentHeight: 480))
        XCTAssertEqual(
            MenuContentLayout.scrollFrameHeight(measuredHeight: 240, maxVisibleContentHeight: 480),
            240
        )
    }

    func testTallContentStaysScrollable() {
        XCTAssertTrue(MenuContentLayout.needsScroll(measuredHeight: 820, maxVisibleContentHeight: 480))
        XCTAssertEqual(
            MenuContentLayout.scrollFrameHeight(measuredHeight: 820, maxVisibleContentHeight: 480),
            480
        )
    }

    func testBenchmarkContentUsesSameSizingRules() {
        XCTAssertFalse(MenuContentLayout.needsScroll(measuredHeight: 300, maxVisibleContentHeight: 480))
        XCTAssertTrue(MenuContentLayout.needsScroll(measuredHeight: 700, maxVisibleContentHeight: 480))
    }
}
