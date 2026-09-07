import XCTest
@testable import MenuStatus

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testShowBenchmarkDefaultsToTrue() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.showBenchmark)
    }

    @MainActor
    func testBenchmarkRefreshIntervalDefaultsToOneHour() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.benchmarkRefreshInterval, SettingsStore.defaultBenchmarkRefreshInterval)
    }

    @MainActor
    func testBenchmarkRefreshIntervalPersistsAcrossStoreRecreation() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let settings = SettingsStore(defaults: defaults)
        settings.benchmarkRefreshInterval = 21_600

        XCTAssertEqual(SettingsStore(defaults: defaults).benchmarkRefreshInterval, 21_600)
    }

    @MainActor
    func testShowBenchmarkPersistsAcrossStoreRecreation() {
        let defaults = makeIsolatedDefaults(testName: #function)

        let firstSettings = SettingsStore(defaults: defaults)
        firstSettings.showBenchmark = false

        let secondSettings = SettingsStore(defaults: defaults)
        XCTAssertFalse(secondSettings.showBenchmark)
    }

    private func makeIsolatedDefaults(testName: String) -> UserDefaults {
        let suiteName = "SettingsStoreTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
