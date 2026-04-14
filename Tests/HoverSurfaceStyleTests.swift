import SwiftUI
import XCTest
@testable import MenuStatus

final class HoverSurfaceStyleTests: XCTestCase {
    func testReadableHoverSurfaceUsesStableCardMetrics() {
        XCTAssertEqual(HoverSurfaceStyle.cornerRadius, 12)
        XCTAssertEqual(HoverSurfaceStyle.shadowRadius, 10)
        XCTAssertEqual(HoverSurfaceStyle.shadowYOffset, 4)
        XCTAssertEqual(HoverSurfaceStyle.horizontalPadding, 10)
    }

    func testReadableHoverSurfaceUsesStrongerLightModeTint() {
        XCTAssertEqual(HoverSurfaceStyle.tintOpacity(for: .light), 0.84, accuracy: 0.001)
        XCTAssertEqual(HoverSurfaceStyle.tintOpacity(for: .dark), 0.72, accuracy: 0.001)
    }

    func testRenderedWidthIncludesSurfacePadding() {
        XCTAssertEqual(HoverSurfaceStyle.renderedWidth(forContentWidth: 220), 240)
        XCTAssertEqual(HoverSurfaceStyle.renderedWidth(forContentWidth: 250), 270)
    }
}
