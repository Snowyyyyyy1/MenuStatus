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
        XCTAssertEqual(config.availability, .available)
    }

    func testAvailabilityRejectsBuildProductsBundle() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/Users/snowyy/Code/MenuStatus/.build/Build/Products/Debug/MenuStatus.app"
        )

        XCTAssertFalse(config.isAvailable)
        XCTAssertEqual(config.availability, .buildProducts)
    }

    func testAvailabilityPrefersBuildProductsReasonOverMissingMetadata() {
        let config = UpdaterConfiguration(
            feedURLString: "",
            publicEDKey: "",
            bundlePath: "/Users/snowyy/Code/MenuStatus/.build/Build/Products/Debug/MenuStatus.app"
        )

        XCTAssertFalse(config.isAvailable)
        XCTAssertEqual(config.availability, .buildProducts)
    }

    func testAvailabilityRejectsMissingFeedURL() {
        let config = UpdaterConfiguration(
            feedURLString: "",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/Applications/MenuStatus.app"
        )

        XCTAssertFalse(config.isAvailable)
        XCTAssertEqual(config.availability, .missingFeedURL)
    }

    func testAvailabilityRejectsMissingPublicKey() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "",
            bundlePath: "/Applications/MenuStatus.app"
        )

        XCTAssertFalse(config.isAvailable)
        XCTAssertEqual(config.availability, .missingPublicKey)
    }

    func testAvailabilityRejectsNonAppBundlePath() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/usr/local/bin/MenuStatus"
        )

        XCTAssertFalse(config.isAvailable)
        XCTAssertEqual(config.availability, .notInstalledToApplications)
    }

    func testAvailabilityRejectsAppOutsideApplicationsDirectory() {
        let config = UpdaterConfiguration(
            feedURLString: "https://snowyyyyyy1.github.io/MenuStatus/appcast.xml",
            publicEDKey: "PUBLIC_KEY",
            bundlePath: "/Users/snowyy/Downloads/MenuStatus.app"
        )

        XCTAssertFalse(config.isAvailable)
        XCTAssertEqual(config.availability, .notInstalledToApplications)
    }

    func testAvailabilityMessageExplainsWhyUpdatesAreDisabled() {
        XCTAssertEqual(
            UpdaterAvailability.notInstalledToApplications.diagnosticMessage,
            "Install MenuStatus to /Applications to enable in-app updates."
        )
        XCTAssertEqual(
            UpdaterAvailability.buildProducts.diagnosticMessage,
            "In-app updates are unavailable in local build products."
        )
    }
}
