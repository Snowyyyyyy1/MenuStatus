import XCTest
@testable import MenuStatus

final class BenchmarkVendorPresentationTests: XCTestCase {
    func testDisplayNameKeepsCanonicalBrandCasing() {
        XCTAssertEqual(BenchmarkVendorPresentation.displayName(for: "anthropic"), "Anthropic")
        XCTAssertEqual(BenchmarkVendorPresentation.displayName(for: "deepseek"), "DeepSeek")
        XCTAssertEqual(BenchmarkVendorPresentation.displayName(for: "glm"), "GLM")
        XCTAssertEqual(BenchmarkVendorPresentation.displayName(for: "openai"), "OpenAI")
        XCTAssertEqual(BenchmarkVendorPresentation.displayName(for: "xai"), "xAI")
    }

    func testOrderedVendorIDsSortByDisplayNameAndDeduplicate() {
        let ordered = BenchmarkVendorPresentation.orderedVendorIDs(
            from: ["openai", "xai", "anthropic", "glm", "deepseek", "openai", "google"]
        )

        XCTAssertEqual(ordered, ["anthropic", "deepseek", "glm", "google", "openai", "xai"])
    }

    func testChipTextUsesKnownAliasesAndUnknownFallback() {
        XCTAssertEqual(BenchmarkVendorPresentation.chipText(for: "openai"), "OAI")
        XCTAssertEqual(BenchmarkVendorPresentation.chipText(for: "xai"), "XAI")
        XCTAssertEqual(BenchmarkVendorPresentation.chipText(for: "unknown"), "UNK")
    }
}
