import XCTest
@testable import MenuStatus

final class UpdaterServiceTests: XCTestCase {
    func testAvailabilityRequiresFeedKeyAndInstalledAppBundle() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/Applications/MenuStatus.app"
        )

        XCTAssertTrue(config.isAvailable)
    }

    func testAvailabilityRejectsBuildProductsBundle() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/Users/snowyy/Code/MenuStatus/.build/Build/Products/Debug/MenuStatus.app"
        )

        XCTAssertFalse(config.isAvailable)
    }

    func testAvailabilityRejectsMissingMetadata() {
        XCTAssertFalse(
            UpdaterConfiguration(
                feedURLString: "",
                publicEDKey: "PUBLIC_KEY",
                bundlePath: "/Applications/MenuStatus.app"
            ).isAvailable
        )
        XCTAssertFalse(
            UpdaterConfiguration(
                feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
                publicEDKey: "",
                bundlePath: "/Applications/MenuStatus.app"
            ).isAvailable
        )
    }

    func testAvailabilityRejectsNonAppBundlePath() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/usr/local/bin/MenuStatus"
        )

        XCTAssertFalse(config.isAvailable)
    }
}
