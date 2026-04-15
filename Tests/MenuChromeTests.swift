import XCTest
import SwiftUI
@testable import MenuStatus

final class MenuChromeTests: XCTestCase {
    func testTabGridRowCountRoundsUpAcrossThreeColumns() {
        XCTAssertEqual(MenuTabGridLayout.rowCount(for: 0), 0)
        XCTAssertEqual(MenuTabGridLayout.rowCount(for: 1), 1)
        XCTAssertEqual(MenuTabGridLayout.rowCount(for: 3), 1)
        XCTAssertEqual(MenuTabGridLayout.rowCount(for: 4), 2)
        XCTAssertEqual(MenuTabGridLayout.rowCount(for: 7), 3)
    }

    func testTabGridColumnWidthUsesThreeFixedSlotsAcrossProviderHeader() {
        let availableWidth = MenuContentSizing.width - MenuTabGridLayout.providerHorizontalPadding * 2
        let columnWidth = MenuTabGridLayout.columnWidth(forAvailableWidth: availableWidth)

        XCTAssertEqual(
            columnWidth * CGFloat(MenuTabGridLayout.columns)
                + MenuTabGridLayout.spacing * CGFloat(MenuTabGridLayout.columns - 1),
            availableWidth,
            accuracy: 0.001
        )
    }

    @MainActor
    func testAppDoesNotTerminateAfterLastWindowClosed() {
        let delegate = MenuStatusAppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testSettingsWindowPresenterReusesSingleWindow() {
        let presenter = SettingsWindowPresenter()

        let firstWindow = presenter.show {
            Text("Settings")
        }
        firstWindow?.orderOut(nil)

        let secondWindow = presenter.show {
            Text("Settings Updated")
        }

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(firstWindow === secondWindow)
        XCTAssertEqual(secondWindow?.title, "Settings")
        XCTAssertTrue(secondWindow?.isVisible ?? false)
        XCTAssertFalse(secondWindow?.styleMask.contains(.resizable) ?? true)
    }
}
