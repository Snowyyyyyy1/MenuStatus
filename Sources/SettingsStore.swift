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
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    var disabledProviderIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledProviderIDs), forKey: Keys.disabledProviderIDs)
        }
    }

    var iconStyle: MenuBarIconStyle {
        didSet { UserDefaults.standard.set(iconStyle.rawValue, forKey: Keys.iconStyle) }
    }

    var customProviderNames: [String: String] {
        didSet { UserDefaults.standard.set(customProviderNames, forKey: Keys.customProviderNames) }
    }

    var providerOrder: [String] {
        didSet { UserDefaults.standard.set(providerOrder, forKey: Keys.providerOrder) }
    }

    var removedBuiltInIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(removedBuiltInIDs), forKey: Keys.removedBuiltInIDs)
        }
    }

    var benchmarkSectionExpanded: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(benchmarkSectionExpanded), forKey: Keys.benchmarkSectionExpanded)
        }
    }

    func displayName(for provider: ProviderConfig) -> String {
        if let custom = customProviderNames[provider.id], !custom.isEmpty {
            return custom
        }
        return provider.displayName
    }

    private(set) var providerConfigs: ProviderConfigStore!

    init() {
        let defaults = UserDefaults.standard

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
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviderIDs = "disabledProviderIDs"
        static let iconStyle = "iconStyle"
        static let customProviderNames = "customProviderNames"
        static let providerOrder = "providerOrder"
        static let removedBuiltInIDs = "removedBuiltInIDs"
        static let benchmarkSectionExpanded = "benchmarkSectionExpanded"
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
