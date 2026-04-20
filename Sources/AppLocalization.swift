import AppKit
import SwiftUI

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    var effectiveLocale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    var effectiveLanguageCode: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.identifier
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }
}

enum AppStrings {
    static func languagePreferenceName(_ preference: AppLanguagePreference, locale: Locale) -> String {
        switch preference {
        case .system:
            return localizedString("settings.language.system", locale: locale, defaultValue: "Follow System")
        case .english:
            return localizedString("settings.language.english", locale: locale, defaultValue: "English")
        case .simplifiedChinese:
            return localizedString("settings.language.simplified-chinese", locale: locale, defaultValue: "Simplified Chinese")
        }
    }

    static func refreshIntervalLabel(_ interval: TimeInterval, locale: Locale) -> String {
        switch Int(interval) {
        case 30:
            return localizedString("settings.refresh.30-seconds", locale: locale, defaultValue: "30 seconds")
        case 60:
            return localizedString("settings.refresh.1-minute", locale: locale, defaultValue: "1 minute")
        case 120:
            return localizedString("settings.refresh.2-minutes", locale: locale, defaultValue: "2 minutes")
        case 300:
            return localizedString("settings.refresh.5-minutes", locale: locale, defaultValue: "5 minutes")
        case 600:
            return localizedString("settings.refresh.10-minutes", locale: locale, defaultValue: "10 minutes")
        default:
            return format(
                "settings.refresh.custom-minutes",
                locale: locale,
                defaultValue: "%lld minutes",
                Int64(max(1, interval / 60))
            )
        }
    }

    static func menuBarIconStyleName(_ style: MenuBarIconStyle, locale: Locale) -> String {
        switch style {
        case .outline:
            return localizedString("settings.icon.outline", locale: locale, defaultValue: "Outline")
        case .filled:
            return localizedString("settings.icon.filled", locale: locale, defaultValue: "Filled")
        case .tinted:
            return localizedString("settings.icon.tinted", locale: locale, defaultValue: "Tinted")
        }
    }

    static func statusIndicatorName(_ indicator: StatusIndicator, locale: Locale) -> String {
        switch indicator {
        case .none:
            return localizedString("status.indicator.operational", locale: locale, defaultValue: "Operational")
        case .minor:
            return localizedString("status.indicator.minor", locale: locale, defaultValue: "Minor Issues")
        case .major:
            return localizedString("status.indicator.major", locale: locale, defaultValue: "Major Outage")
        case .critical:
            return localizedString("status.indicator.critical", locale: locale, defaultValue: "Critical Outage")
        case .maintenance:
            return localizedString("status.indicator.maintenance", locale: locale, defaultValue: "Maintenance")
        }
    }

    static func impactLabel(_ indicator: StatusIndicator, locale: Locale) -> String {
        switch indicator {
        case .none:
            return localizedString("status.impact.none", locale: locale, defaultValue: "None")
        case .minor:
            return localizedString("status.impact.minor", locale: locale, defaultValue: "Minor")
        case .major:
            return localizedString("status.impact.major", locale: locale, defaultValue: "Major")
        case .critical:
            return localizedString("status.impact.critical", locale: locale, defaultValue: "Critical")
        case .maintenance:
            return localizedString("status.impact.maintenance", locale: locale, defaultValue: "Maintenance")
        }
    }

    static func componentStatusName(_ status: ComponentStatus, locale: Locale) -> String {
        switch status {
        case .operational:
            return localizedString("component.status.operational", locale: locale, defaultValue: "Operational")
        case .degradedPerformance:
            return localizedString("component.status.degraded", locale: locale, defaultValue: "Degraded")
        case .partialOutage:
            return localizedString("component.status.partial-outage", locale: locale, defaultValue: "Partial Outage")
        case .majorOutage:
            return localizedString("component.status.major-outage", locale: locale, defaultValue: "Major Outage")
        case .underMaintenance:
            return localizedString("component.status.maintenance", locale: locale, defaultValue: "Maintenance")
        }
    }

    static func timelineDayLevelName(_ level: TimelineDayLevel, locale: Locale) -> String {
        switch level {
        case .noData:
            return localizedString("timeline.level.no-data", locale: locale, defaultValue: "No data")
        case .operational:
            return localizedString("timeline.level.operational", locale: locale, defaultValue: "Operational")
        case .degraded:
            return localizedString("timeline.level.degraded", locale: locale, defaultValue: "Degraded")
        case .maintenance:
            return localizedString("timeline.level.maintenance", locale: locale, defaultValue: "Maintenance")
        case .partialOutage:
            return localizedString("timeline.level.partial-outage", locale: locale, defaultValue: "Partial Outage")
        case .majorOutage:
            return localizedString("timeline.level.major-outage", locale: locale, defaultValue: "Major Outage")
        }
    }

    static func relatedIncidentsTitle(locale: Locale) -> String {
        localizedString("tooltip.related", locale: locale, defaultValue: "RELATED")
    }

    static func updatedString(
        since updatedDate: Date,
        referenceDate: Date = .now,
        locale: Locale
    ) -> String {
        let elapsedSeconds = max(1, Int(referenceDate.timeIntervalSince(updatedDate)))
        if elapsedSeconds < 60 {
            return localizedVariantFormat(
                locale: locale,
                chineseKey: "footer.updated-seconds.zh",
                chineseDefault: "%lld 秒前更新",
                englishKey: "footer.updated-seconds.en",
                englishDefault: "Updated %lld sec ago",
                Int64(elapsedSeconds)
            )
        }

        let elapsedMinutes = max(1, elapsedSeconds / 60)
        return localizedVariantFormat(
            locale: locale,
            chineseKey: "footer.updated-minutes.zh",
            chineseDefault: "%lld 分钟前更新",
            englishKey: "footer.updated-minutes.en",
            englishDefault: "Updated %lld min ago",
            Int64(elapsedMinutes)
        )
    }

    static func durationString(_ seconds: TimeInterval, locale: Locale) -> String {
        let totalSeconds = max(60, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = max(1, (totalSeconds % 3600) / 60)

        if hours > 0 {
            return localizedVariantFormat(
                locale: locale,
                chineseKey: "duration.hours-minutes.zh",
                chineseDefault: "%lld 小时 %lld 分钟",
                englishKey: "duration.hours-minutes.en",
                englishDefault: "%lld hr %lld min",
                Int64(hours),
                Int64(minutes)
            )
        }

        return localizedVariantFormat(
            locale: locale,
            chineseKey: "duration.minutes.zh",
            chineseDefault: "%lld 分钟",
            englishKey: "duration.minutes.en",
            englishDefault: "%lld min",
            Int64(minutes)
        )
    }

    static func tooltipDateString(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        return formatter.string(from: date)
    }

    static func componentCountString(_ count: Int, locale: Locale) -> String {
        if isChinese(locale) {
            return format(
                "count.components.zh",
                locale: locale,
                defaultValue: "%lld 个组件",
                Int64(count)
            )
        }

        let key = count == 1 ? "count.component.en" : "count.components.en"
        let defaultValue = count == 1 ? "%lld component" : "%lld components"
        return format(key, locale: locale, defaultValue: defaultValue, Int64(count))
    }

    static func modelCountString(_ count: Int, locale: Locale) -> String {
        if isChinese(locale) {
            return format(
                "count.models.zh",
                locale: locale,
                defaultValue: "%lld 个模型",
                Int64(count)
            )
        }

        let key = count == 1 ? "count.model.en" : "count.models.en"
        let defaultValue = count == 1 ? "%lld model" : "%lld models"
        return format(key, locale: locale, defaultValue: defaultValue, Int64(count))
    }

    static func uptimeString(_ uptimePercent: Double, isEstimated: Bool, locale: Locale) -> String {
        let percent = String(format: "%.2f", locale: locale, uptimePercent)
        if isChinese(locale) {
            return isEstimated ? "≈ \(percent)% 可用性" : "\(percent)% 可用性"
        }
        return isEstimated ? "≈ \(percent)% uptime" : "\(percent)% uptime"
    }

    static func averageScoreString(_ value: Int, locale: Locale) -> String {
        return localizedVariantFormat(
            locale: locale,
            chineseKey: "benchmark.average.zh",
            chineseDefault: "均分 %lld",
            englishKey: "benchmark.average.en",
            englishDefault: "avg %lld",
            Int64(value)
        )
    }

    static func trustString(_ value: Int, locale: Locale) -> String {
        return localizedVariantFormat(
            locale: locale,
            chineseKey: "benchmark.trust.zh",
            chineseDefault: "可信度 %lld",
            englishKey: "benchmark.trust.en",
            englishDefault: "Trust %lld",
            Int64(value)
        )
    }

    static func nextBenchmarkString(_ value: String, locale: Locale) -> String {
        return localizedVariantFormat(
            locale: locale,
            chineseKey: "benchmark.next-run.zh",
            chineseDefault: "下次评测：%@",
            englishKey: "benchmark.next-run.en",
            englishDefault: "Next benchmark: %@",
            value
        )
    }

    static func freshnessLabel(relative: String, isStale: Bool, locale: Locale) -> String {
        if isStale {
            return localizedVariantFormat(
                locale: locale,
                chineseKey: "benchmark.freshness.stale.zh",
                chineseDefault: "数据过期 • %@",
                englishKey: "benchmark.freshness.stale.en",
                englishDefault: "Stale • %@",
                relative
            )
        }

        return localizedVariantFormat(
            locale: locale,
            chineseKey: "benchmark.freshness.updated.zh",
            chineseDefault: "已更新 • %@",
            englishKey: "benchmark.freshness.updated.en",
            englishDefault: "Updated %@",
            relative
        )
    }

    static func localizedTrendName(_ trend: String, locale: Locale) -> String {
        switch trend.lowercased() {
        case "improving":
            return localizedString("benchmark.trend.improving", locale: locale, defaultValue: "Improving")
        case "declining":
            return localizedString("benchmark.trend.declining", locale: locale, defaultValue: "Declining")
        default:
            return localizedString("benchmark.trend.stable", locale: locale, defaultValue: "Stable")
        }
    }

    static func unknownLabel(locale: Locale) -> String {
        localizedString("common.unknown", locale: locale, defaultValue: "Unknown")
    }

    static func localizedString(_ key: String, locale: Locale, defaultValue: String) -> String {
        localizedBundle(for: locale).localizedString(forKey: key, value: defaultValue, table: nil)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle {
        let localization = localizationIdentifier(for: locale)
        guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static func localizationIdentifier(for locale: Locale) -> String {
        isChinese(locale) ? "zh-Hans" : "en"
    }

    private static func isChinese(_ locale: Locale) -> Bool {
        locale.identifier.hasPrefix("zh") || locale.language.languageCode?.identifier == "zh"
    }

    private static func format(
        _ key: String,
        locale: Locale,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        let format = localizedString(key, locale: locale, defaultValue: defaultValue)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizedVariantFormat(
        locale: Locale,
        chineseKey: String,
        chineseDefault: String,
        englishKey: String,
        englishDefault: String,
        _ arguments: CVarArg...
    ) -> String {
        let key = isChinese(locale) ? chineseKey : englishKey
        let defaultValue = isChinese(locale) ? chineseDefault : englishDefault
        let formatString = localizedString(key, locale: locale, defaultValue: defaultValue)
        return String(format: formatString, locale: locale, arguments: arguments)
    }
}

struct LocalizedMenuRootView: View {
    @Bindable var settings: SettingsStore
    let store: StatusStore
    let benchmarkStore: AIStupidLevelStore
    let hostCoordinator: MenuHostCoordinator

    var body: some View {
        StatusMenuContentView(
            store: store,
            benchmarkStore: benchmarkStore,
            hostCoordinator: hostCoordinator
        )
        .environment(\.locale, settings.effectiveLocale)
    }
}

struct LocalizedSettingsRootView: View {
    @Bindable var settings: SettingsStore
    var store: StatusStore?
    var updaterService: UpdaterService

    var body: some View {
        SettingsView(settings: settings, store: store, updaterService: updaterService)
            .environment(\.locale, settings.effectiveLocale)
    }
}
