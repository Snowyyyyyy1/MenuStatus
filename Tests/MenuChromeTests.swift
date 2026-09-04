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

    func testSettingsSceneBridgePrefersNativeSettingsAction() {
        var nativeActionCount = 0
        var fallbackCount = 0

        SettingsSceneBridge.performOpenRequest(
            sendNativeAction: {
                nativeActionCount += 1
                return true
            },
            postFallbackNotification: {
                fallbackCount += 1
            }
        )

        XCTAssertEqual(nativeActionCount, 1)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testSettingsSceneBridgeFallsBackWhenNativeActionIsUnavailable() {
        var fallbackCount = 0

        SettingsSceneBridge.performOpenRequest(
            sendNativeAction: { false },
            postFallbackNotification: {
                fallbackCount += 1
            }
        )

        XCTAssertEqual(fallbackCount, 1)
    }

    func testSettingsSceneBridgeFindsCommandCommaSettingsItem() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "MenuStatus", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: Selector(("testAction:")),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        appMenu.addItem(settingsItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        XCTAssertTrue(SettingsSceneBridge.settingsMenuItem(in: mainMenu) === settingsItem)
    }

    func testSettingsSceneBridgeIgnoresNonCommandCommaItems() {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Comma",
            action: Selector(("testAction:")),
            keyEquivalent: ","
        )
        item.keyEquivalentModifierMask = []
        menu.addItem(item)

        XCTAssertNil(SettingsSceneBridge.settingsMenuItem(in: menu))
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

    func testSettingsDefaultSizeMatchesGeneralPaneContract() {
        XCTAssertEqual(SettingsWindowMetrics.defaultContentSize.width, SettingsPane.general.preferredWidth)
        XCTAssertEqual(SettingsWindowMetrics.defaultContentSize.height, SettingsPane.general.preferredHeight)
        XCTAssertEqual(SettingsWindowContentSizing.targetContentWidth(for: .general), 496)
    }

    func testSettingsProvidersPaneUsesWiderStableContentSize() {
        XCTAssertEqual(SettingsPane.providers.preferredWidth, 720)
        XCTAssertEqual(SettingsPane.providers.preferredHeight, SettingsPane.general.preferredHeight)
        XCTAssertGreaterThan(SettingsPane.providers.preferredWidth, SettingsPane.general.preferredWidth)
        XCTAssertEqual(SettingsWindowContentSizing.targetContentWidth(for: .providers), 720)
    }

    func testSettingsWindowSizingDetectsMeaningfulContentWidthChanges() {
        XCTAssertFalse(
            SettingsWindowContentSizing.needsWidthResize(
                currentContentWidth: 496.2,
                targetContentWidth: SettingsWindowMetrics.defaultContentSize.width
            )
        )
        XCTAssertTrue(
            SettingsWindowContentSizing.needsWidthResize(
                currentContentWidth: SettingsWindowMetrics.defaultContentSize.width,
                targetContentWidth: SettingsWindowContentSizing.targetContentWidth(for: .providers)
            )
        )
    }

    func testSettingsWindowSizingChangesWidthOnly() {
        let resized = SettingsWindowContentSizing.resizedContentSize(
            currentContentSize: NSSize(width: 496, height: 668),
            targetContentWidth: SettingsWindowContentSizing.targetContentWidth(for: .providers)
        )

        XCTAssertEqual(resized.width, SettingsPane.providers.preferredWidth)
        XCTAssertEqual(resized.height, 668)
    }

    func testSettingsPaneCanResolveWindowTitle() {
        XCTAssertEqual(
            SettingsPane.windowTitleMatch("Providers", locale: Locale(identifier: "en")),
            .providers
        )
        XCTAssertEqual(
            SettingsPane.windowTitleMatch("General", locale: Locale(identifier: "zh-Hans")),
            .general
        )
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
