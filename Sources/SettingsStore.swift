import Foundation
import Observation
import ServiceManagement

enum MenuBarIconStyle: Int, CaseIterable {
    case outline = 0
    case filled = 1
    case tinted = 2
}

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    var languagePreference: AppLanguagePreference {
        didSet { defaults.set(languagePreference.rawValue, forKey: Keys.languagePreference) }
    }

    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    var disabledProviderIDs: Set<String> {
        didSet {
            defaults.set(Array(disabledProviderIDs), forKey: Keys.disabledProviderIDs)
        }
    }

    var iconStyle: MenuBarIconStyle {
        didSet { defaults.set(iconStyle.rawValue, forKey: Keys.iconStyle) }
    }

    var customProviderNames: [String: String] {
        didSet { defaults.set(customProviderNames, forKey: Keys.customProviderNames) }
    }

    var providerOrder: [String] {
        didSet { defaults.set(providerOrder, forKey: Keys.providerOrder) }
    }

    var removedBuiltInIDs: Set<String> {
        didSet {
            defaults.set(Array(removedBuiltInIDs), forKey: Keys.removedBuiltInIDs)
        }
    }

    var benchmarkSectionExpanded: Set<String> {
        didSet {
            defaults.set(Array(benchmarkSectionExpanded), forKey: Keys.benchmarkSectionExpanded)
        }
    }

    var groupExpansionOverrides: [String: Bool] {
        didSet {
            defaults.set(groupExpansionOverrides, forKey: Keys.groupExpansionOverrides)
        }
    }

    var allowsBetaUpdates: Bool {
        didSet { defaults.set(allowsBetaUpdates, forKey: Keys.allowsBetaUpdates) }
    }

    func displayName(for provider: ProviderConfig) -> String {
        if let custom = customProviderNames[provider.id], !custom.isEmpty {
            return custom
        }
        return provider.displayName
    }

    var effectiveLocale: Locale {
        languagePreference.effectiveLocale
    }

    var effectiveLanguageCode: String {
        languagePreference.effectiveLanguageCode
    }

    private(set) var providerConfigs: ProviderConfigStore!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawLanguagePreference = defaults.string(forKey: Keys.languagePreference),
           let languagePreference = AppLanguagePreference(rawValue: rawLanguagePreference) {
            self.languagePreference = languagePreference
        } else {
            self.languagePreference = .system
        }

        if let interval = defaults.object(forKey: Keys.refreshInterval) as? TimeInterval, interval > 0 {
            self.refreshInterval = interval
        } else {
            self.refreshInterval = 60
        }

        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        if let ids = defaults.stringArray(forKey: Keys.disabledProviderIDs) {
            self.disabledProviderIDs = Set(ids)
        } else {
            self.disabledProviderIDs = []
        }

        self.iconStyle = MenuBarIconStyle(rawValue: defaults.integer(forKey: Keys.iconStyle)) ?? .outline
        self.customProviderNames = (defaults.dictionary(forKey: Keys.customProviderNames) as? [String: String]) ?? [:]
        self.providerOrder = defaults.stringArray(forKey: Keys.providerOrder) ?? []
        self.removedBuiltInIDs = Set(defaults.stringArray(forKey: Keys.removedBuiltInIDs) ?? [])
        self.benchmarkSectionExpanded = Set(defaults.stringArray(forKey: Keys.benchmarkSectionExpanded) ?? [])
        self.groupExpansionOverrides = (defaults.dictionary(forKey: Keys.groupExpansionOverrides) as? [String: Bool]) ?? [:]
        self.allowsBetaUpdates = defaults.bool(forKey: Keys.allowsBetaUpdates)
    }

    func attachProviderConfigs(_ store: ProviderConfigStore) {
        self.providerConfigs = store
    }

    func isEnabled(_ provider: ProviderConfig) -> Bool {
        !disabledProviderIDs.contains(provider.id)
    }

    func toggleProvider(_ provider: ProviderConfig) {
        if disabledProviderIDs.contains(provider.id) {
            disabledProviderIDs.remove(provider.id)
        } else {
            let enabledCount = providerConfigs.allProviders.count - disabledProviderIDs.count
            guard enabledCount > 1 else { return }
            disabledProviderIDs.insert(provider.id)
        }
    }

    private func updateLoginItem() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private enum Keys {
        static let languagePreference = "languagePreference"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviderIDs = "disabledProviderIDs"
        static let iconStyle = "iconStyle"
        static let customProviderNames = "customProviderNames"
        static let providerOrder = "providerOrder"
        static let removedBuiltInIDs = "removedBuiltInIDs"
        static let benchmarkSectionExpanded = "benchmarkSectionExpanded"
        static let groupExpansionOverrides = "groupExpansionOverrides"
        static let allowsBetaUpdates = UpdaterPreferenceKeys.allowsBetaUpdates
    }
}

extension ProviderConfigStore {
    func orderedProviders(settings: SettingsStore) -> [ProviderConfig] {
        let all = allProviders
        if settings.providerOrder.isEmpty {
            return all
        }
        return all.sorted { a, b in
            let ai = settings.providerOrder.firstIndex(of: a.id) ?? Int.max
            let bi = settings.providerOrder.firstIndex(of: b.id) ?? Int.max
            return ai < bi
        }
    }

    func enabledProviders(settings: SettingsStore) -> [ProviderConfig] {
        orderedProviders(settings: settings).filter { settings.isEnabled($0) }
    }
}
