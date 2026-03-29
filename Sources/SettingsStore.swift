import Foundation
import Observation
import ServiceManagement

enum MenuBarIconStyle: Int, CaseIterable {
    case outline = 0
    case filled = 1
    case tinted = 2
}

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

    let providerConfigs: ProviderConfigStore

    init(providerConfigs: ProviderConfigStore = ProviderConfigStore()) {
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
        self.providerConfigs = providerConfigs
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
        try? SMAppService.mainApp.register()
        if !launchAtLogin {
            try? SMAppService.mainApp.unregister()
        }
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviderIDs = "disabledProviderIDs"
        static let iconStyle = "iconStyle"
    }
}

extension ProviderConfigStore {
    func enabledProviders(settings: SettingsStore) -> [ProviderConfig] {
        allProviders.filter { settings.isEnabled($0) }
    }
}
