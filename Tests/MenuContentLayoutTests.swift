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

    func testUnmeasuredContentUsesLastMeasuredHeightAsProvisionalFrame() {
        XCTAssertEqual(
            MenuContentLayout.provisionalScrollFrameHeight(
                measuredHeight: nil,
                lastMeasuredHeight: 280,
                maxVisibleContentHeight: 480
            ),
            280
        )
    }

    func testUnmeasuredContentFallsBackToDefaultProvisionalHeight() {
        XCTAssertEqual(
            MenuContentLayout.provisionalScrollFrameHeight(
                measuredHeight: nil,
                lastMeasuredHeight: nil,
                maxVisibleContentHeight: 480
            ),
            320
        )
    }

    func testAcceptsNonZeroMeasuredContentHeight() {
        XCTAssertEqual(
            MenuContentLayout.acceptedMeasuredContentHeight(
                previousMeasuredHeight: 280,
                newMeasuredHeight: 240
            ),
            240
        )
    }

    func testRejectsTransientZeroMeasuredContentHeight() {
        XCTAssertEqual(
            MenuContentLayout.acceptedMeasuredContentHeight(
                previousMeasuredHeight: 280,
                newMeasuredHeight: 0
            ),
            280
        )
    }

    func testRejectsTransientZeroMeasurementWithoutPreviousHeight() {
        XCTAssertNil(
            MenuContentLayout.acceptedMeasuredContentHeight(
                previousMeasuredHeight: nil,
                newMeasuredHeight: 0
            )
        )
    }

    func testUsesLastMeasuredFallbackOnlyDuringSelectionTransition() {
        XCTAssertEqual(
            MenuContentLayout.fallbackMeasuredHeight(
                lastMeasuredHeight: 280,
                usesLastMeasuredFallback: true
            ),
            280
        )
        XCTAssertNil(
            MenuContentLayout.fallbackMeasuredHeight(
                lastMeasuredHeight: 280,
                usesLastMeasuredFallback: false
            )
        )
    }

    func testMaxVisibleContentHeightPrefersActualAvailablePopoverHeight() {
        XCTAssertEqual(
            MenuContentLayout.maxVisibleContentHeight(
                availablePopoverHeight: 540,
                fallbackScreenHeight: 900,
                headerHeight: 84,
                footerHeight: 46
            ),
            410
        )
    }

    func testMaxVisibleContentHeightFallsBackToScreenEstimate() {
        XCTAssertEqual(
            MenuContentLayout.maxVisibleContentHeight(
                availablePopoverHeight: nil,
                fallbackScreenHeight: 900,
                headerHeight: 84,
                footerHeight: 46
            ),
            750
        )
    }

    func testMaxVisibleContentHeightUsesMinimumWhenAvailableSpaceIsVerySmall() {
        XCTAssertEqual(
            MenuContentLayout.maxVisibleContentHeight(
                availablePopoverHeight: 280,
                fallbackScreenHeight: 900,
                headerHeight: 84,
                footerHeight: 46
            ),
            200
        )
    }

    func testVisibleContentHeightUsesMeasuredHeightWhenNoScrollIsNeeded() {
        XCTAssertEqual(
            MenuContentLayout.visibleContentHeight(
                measuredHeight: 260,
                lastMeasuredHeight: 420,
                maxVisibleContentHeight: 480
            ),
            260
        )
    }

    func testPreferredPopoverHeightUsesStableProvisionalContentDuringSelectionSwitch() {
        XCTAssertEqual(
            MenuContentLayout.preferredPopoverHeight(
                headerHeight: 80,
                footerHeight: 44,
                measuredContentHeight: nil,
                lastMeasuredContentHeight: 300,
                maxVisibleContentHeight: 480
            ),
            424
        )
    }

    func testPopoverResizeWaitsForStableChromeMeasurements() {
        XCTAssertFalse(
            MenuContentLayout.shouldRequestPopoverResize(
                headerHeight: 0,
                footerHeight: 44,
                initialMeasurementDone: true
            )
        )
        XCTAssertFalse(
            MenuContentLayout.shouldRequestPopoverResize(
                headerHeight: 80,
                footerHeight: 0,
                initialMeasurementDone: true
            )
        )
        XCTAssertFalse(
            MenuContentLayout.shouldRequestPopoverResize(
                headerHeight: 80,
                footerHeight: 44,
                initialMeasurementDone: false
            )
        )
        XCTAssertTrue(
            MenuContentLayout.shouldRequestPopoverResize(
                headerHeight: 80,
                footerHeight: 44,
                initialMeasurementDone: true
            )
        )
    }

    func testPopoverResizePolicyIgnoresTinyHeightChanges() {
        XCTAssertEqual(
            PopoverResizePolicy.mode(currentHeight: 300, targetHeight: 300.2),
            .ignore
        )
    }

    func testPopoverResizePolicyExpandsImmediately() {
        XCTAssertEqual(
            PopoverResizePolicy.mode(currentHeight: 280, targetHeight: 420),
            .immediate
        )
    }

    func testPopoverResizePolicyDefersShrink() {
        XCTAssertEqual(
            PopoverResizePolicy.mode(currentHeight: 420, targetHeight: 280),
            .deferred(delay: .milliseconds(120))
        )
    }

    func testPopoverResizePolicyShrinksImmediatelyDuringSelectionTransition() {
        XCTAssertEqual(
            PopoverResizePolicy.mode(
                currentHeight: 420,
                targetHeight: 280,
                isSelectionTransitionActive: true
            ),
            .immediate
        )
    }
}
