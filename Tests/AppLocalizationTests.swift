import XCTest
@testable import MenuStatus

final class AppLocalizationTests: XCTestCase {
    @MainActor
    func testLanguagePreferenceDefaultsToSystem() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.languagePreference, .system)
        XCTAssertEqual(settings.effectiveLocale.identifier, Locale.autoupdatingCurrent.identifier)
    }

    @MainActor
    func testLanguagePreferencePersistsAcrossStoreRecreation() {
        let defaults = makeIsolatedDefaults(testName: #function)

        let firstSettings = SettingsStore(defaults: defaults)
        firstSettings.languagePreference = .simplifiedChinese

        let secondSettings = SettingsStore(defaults: defaults)

        XCTAssertEqual(secondSettings.languagePreference, .simplifiedChinese)
        XCTAssertEqual(secondSettings.effectiveLanguageCode, "zh-Hans")
        XCTAssertEqual(secondSettings.effectiveLocale.identifier, "zh-Hans")
    }

    @MainActor
    func testLanguagePreferenceResolvesEnglishLocale() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let settings = SettingsStore(defaults: defaults)

        settings.languagePreference = .english

        XCTAssertEqual(settings.effectiveLanguageCode, "en")
        XCTAssertEqual(settings.effectiveLocale.identifier, "en")
    }

    func testLocalizedStatusStringsUseChineseTranslations() {
        let locale = Locale(identifier: "zh-Hans")

        XCTAssertEqual(AppStrings.statusIndicatorName(.none, locale: locale), "正常")
        XCTAssertEqual(AppStrings.componentStatusName(.degradedPerformance, locale: locale), "降级")
        XCTAssertEqual(AppStrings.timelineDayLevelName(.majorOutage, locale: locale), "重大故障")
        XCTAssertEqual(AppStrings.relatedIncidentsTitle(locale: locale), "相关")
    }

    func testLocalizedCountStringsHandleEnglishAndChinese() {
        XCTAssertEqual(AppStrings.componentCountString(1, locale: Locale(identifier: "en")), "1 component")
        XCTAssertEqual(AppStrings.componentCountString(3, locale: Locale(identifier: "en")), "3 components")
        XCTAssertEqual(AppStrings.componentCountString(2, locale: Locale(identifier: "zh-Hans")), "2 个组件")

        XCTAssertEqual(AppStrings.modelCountString(1, locale: Locale(identifier: "en")), "1 model")
        XCTAssertEqual(AppStrings.modelCountString(4, locale: Locale(identifier: "en")), "4 models")
        XCTAssertEqual(AppStrings.modelCountString(5, locale: Locale(identifier: "zh-Hans")), "5 个模型")
    }

    func testLocalizedUpdatedStringWrapsRelativeTimePerLocale() {
        let referenceDate = Date(timeIntervalSince1970: 1_775_000_000)
        let updatedDate = referenceDate.addingTimeInterval(-120)

        let english = AppStrings.updatedString(
            since: updatedDate,
            referenceDate: referenceDate,
            locale: Locale(identifier: "en")
        )
        let chinese = AppStrings.updatedString(
            since: updatedDate,
            referenceDate: referenceDate,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertTrue(english.contains("Updated"))
        XCTAssertTrue(english.localizedCaseInsensitiveContains("min"))
        XCTAssertTrue(chinese.contains("更新"))
        XCTAssertTrue(chinese.contains("前"))
        XCTAssertFalse(chinese.contains("Updated"))
    }

    func testLocalizedDurationStringChangesWithLocale() {
        let english = AppStrings.durationString(3660, locale: Locale(identifier: "en"))
        let chinese = AppStrings.durationString(3660, locale: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(english, "1 hr 1 min")
        XCTAssertEqual(chinese, "1 小时 1 分钟")
    }

    func testTooltipDateStringUsesLocaleAwareOutput() {
        let date = Date(timeIntervalSince1970: 1_709_337_600) // 2024-03-04 00:00:00 UTC
        let english = AppStrings.tooltipDateString(date, locale: Locale(identifier: "en"))
        let chinese = AppStrings.tooltipDateString(date, locale: Locale(identifier: "zh-Hans"))

        XCTAssertNotEqual(english, chinese)
        XCTAssertTrue(chinese.contains("年") || chinese.contains("月"))
    }

    func testSettingsOptionNamesUseLocalizedCopy() {
        XCTAssertEqual(
            AppStrings.menuBarIconStyleName(.filled, locale: Locale(identifier: "en")),
            "Filled"
        )
        XCTAssertEqual(
            AppStrings.menuBarIconStyleName(.tinted, locale: Locale(identifier: "zh-Hans")),
            "着色"
        )
        XCTAssertEqual(
            AppStrings.languagePreferenceName(.system, locale: Locale(identifier: "zh-Hans")),
            "跟随系统"
        )
        XCTAssertEqual(
            AppStrings.refreshIntervalLabel(300, locale: Locale(identifier: "zh-Hans")),
            "5 分钟"
        )
    }

    private func makeIsolatedDefaults(testName: String) -> UserDefaults {
        let suiteName = "AppLocalizationTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
