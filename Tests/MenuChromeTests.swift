import XCTest
import SwiftUI
@testable import MenuStatus

final class MenuChromeTests: XCTestCase {
    func testResolveLayoutFitsAllTabsOnOneRowWhenRoomAllows() {
        let widths: [CGFloat] = [80, 80]
        let plan = MenuTabGridLayout.resolveLayout(widths: widths, availableWidth: 340)

        XCTAssertEqual(plan.rowCount, 1)
        XCTAssertEqual(plan.perRow, 2)
        XCTAssertGreaterThanOrEqual(plan.uniformWidth, 80)
    }

    func testResolveLayoutExpandsUniformWidthWhenTwoTabsShareAvailableRow() {
        let widths: [CGFloat] = [60, 60]
        let plan = MenuTabGridLayout.resolveLayout(widths: widths, availableWidth: 340)

        XCTAssertEqual(plan.rowCount, 1)
        XCTAssertEqual(plan.perRow, 2)
        // Two tabs on one row should fill available width: (340 - spacing) / 2 ≈ 168.
        XCTAssertEqual(plan.uniformWidth, floor((340 - MenuTabGridLayout.spacing) / 2), accuracy: 0.001)
    }

    func testResolveLayoutWrapsToSecondRowWhenContentDoesNotFit() {
        // Five tabs each requiring 100pt; one row would allow only (340 - 16)/5 = 64.8 < 100.
        let widths: [CGFloat] = Array(repeating: 100, count: 5)
        let plan = MenuTabGridLayout.resolveLayout(widths: widths, availableWidth: 340)

        XCTAssertEqual(plan.rowCount, 2)
        XCTAssertEqual(plan.perRow, 3)
    }

    func testResolveLayoutReturnsEmptyPlanForNoTabs() {
        let plan = MenuTabGridLayout.resolveLayout(widths: [], availableWidth: 340)

        XCTAssertEqual(plan.rowCount, 0)
        XCTAssertEqual(plan.perRow, 0)
        XCTAssertEqual(plan.uniformWidth, 0)
    }

    func testTabContentWidthAccountsForStatusDot() {
        let plain = MenuTabGridLayout.tabContentWidth(text: "OpenAI")
        let dotted = MenuTabGridLayout.tabContentWidth(text: "OpenAI", hasLeadingDot: true)

        let expectedExtra = MenuTabGridLayout.statusDotWidth + MenuTabGridLayout.tabInnerSpacing
        XCTAssertEqual(dotted - plain, expectedExtra, accuracy: 0.001)
    }

    func testRowRangeSplitsTabsAcrossRowsLeftToRight() {
        XCTAssertEqual(MenuTabGridLayout.rowRange(count: 5, perRow: 3, rowIndex: 0), 0..<3)
        XCTAssertEqual(MenuTabGridLayout.rowRange(count: 5, perRow: 3, rowIndex: 1), 3..<5)
        XCTAssertEqual(MenuTabGridLayout.rowRange(count: 0, perRow: 3, rowIndex: 0), 0..<0)
    }

    @MainActor
    func testAppDoesNotTerminateAfterLastWindowClosed() {
        let delegate = MenuStatusAppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testSettingsSceneBridgePostsOpenNotification() {
        let expectation = expectation(
            forNotification: SettingsSceneBridge.openNotification,
            object: nil
        )

        SettingsSceneBridge.requestOpen()

        wait(for: [expectation], timeout: 0.2)
    }

    func testSettingsProviderSelectionDefaultsToFirstProvider() {
        let providers = [ProviderConfig.openAI, ProviderConfig.anthropic]

        let selection = SettingsProviderSelection.resolvedSelection(
            current: nil,
            providers: providers
        )

        XCTAssertEqual(selection, ProviderConfig.openAI.id)
    }

    func testSettingsProviderSelectionFallsBackWhenCurrentProviderDisappears() {
        let providers = [ProviderConfig.openAI, ProviderConfig.anthropic]

        let selection = SettingsProviderSelection.resolvedSelection(
            current: "missing-provider",
            providers: providers
        )

        XCTAssertEqual(selection, ProviderConfig.openAI.id)
    }

    func testSettingsProviderSelectionKeepsCurrentProviderWhenStillAvailable() {
        let providers = [ProviderConfig.openAI, ProviderConfig.anthropic]

        let selection = SettingsProviderSelection.resolvedSelection(
            current: ProviderConfig.anthropic.id,
            providers: providers
        )

        XCTAssertEqual(selection, ProviderConfig.anthropic.id)
    }

    func testProviderUtilitySectionHidesResetButtonWhenNoBuiltInsWereRemoved() {
        XCTAssertFalse(
            ProviderUtilitySectionState.showsResetBuiltInsButton(removedBuiltInIDs: [])
        )
    }

    func testProviderUtilitySectionShowsResetButtonWhenBuiltInsWereRemoved() {
        XCTAssertTrue(
            ProviderUtilitySectionState.showsResetBuiltInsButton(
                removedBuiltInIDs: [ProviderConfig.openAI.id]
            )
        )
    }

    func testSettingsWindowSizingKeepsWindowTopEdgeFixed() {
        let currentFrame = NSRect(x: 120, y: 320, width: 496, height: 580)

        let targetFrame = SettingsWindowSizing.targetFrame(
            currentFrame: currentFrame,
            targetFrameSize: NSSize(width: 720, height: 580)
        )

        XCTAssertEqual(targetFrame.origin.x, 120)
        XCTAssertEqual(targetFrame.maxY, currentFrame.maxY)
        XCTAssertEqual(targetFrame.width, 720)
        XCTAssertEqual(targetFrame.height, 580)
    }

    func testSettingsWindowSizingAdjustsHeightWhilePreservingTopEdge() {
        let currentFrame = NSRect(x: 120, y: 320, width: 496, height: 580)

        let targetFrame = SettingsWindowSizing.targetFrame(
            currentFrame: currentFrame,
            targetFrameSize: NSSize(width: 496, height: 620)
        )

        XCTAssertEqual(targetFrame.origin.x, 120)
        XCTAssertEqual(targetFrame.maxY, currentFrame.maxY)
        XCTAssertEqual(targetFrame.width, 496)
        XCTAssertEqual(targetFrame.height, 620)
    }

    func testAboutLinkDestinationsExposeExpectedURLs() {
        XCTAssertEqual(AboutLinkDestination.github.urlString, "https://github.com/Snowyyyyyy1/MenuStatus")
        XCTAssertEqual(AboutLinkDestination.reportIssue.urlString, "https://github.com/Snowyyyyyy1/MenuStatus/issues/new/choose")
        XCTAssertEqual(AboutLinkDestination.releases.urlString, "https://github.com/Snowyyyyyy1/MenuStatus/releases")
    }

    func testAboutLinkDestinationsExposeStableOrdering() {
        XCTAssertEqual(AboutLinkDestination.allCases, [.github, .reportIssue, .releases])
    }

    func testProviderUtilityPlacementUsesSidebarFooter() {
        XCTAssertEqual(ProviderUtilitySectionPlacement.default, .sidebarFooter)
    }
}
