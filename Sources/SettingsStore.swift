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
    static let defaultBenchmarkRefreshInterval: TimeInterval = 3600
    static let benchmarkRefreshIntervalOptions: [TimeInterval] = [3600, 21600, 86400]

    private let defaults: UserDefaults
    private var benchmarkAPIKeyValue: String
    private var isApplyingLaunchAtLogin = false

    var languagePreference: AppLanguagePreference {
        didSet { defaults.set(languagePreference.rawValue, forKey: Keys.languagePreference) }
    }

    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    var benchmarkRefreshInterval: TimeInterval {
        didSet {
            let normalized = max(60, benchmarkRefreshInterval)
            if benchmarkRefreshInterval != normalized {
                benchmarkRefreshInterval = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.benchmarkRefreshInterval)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLaunchAtLogin else { return }
            applyLaunchAtLoginChange(requested: launchAtLogin, previous: oldValue)
        }
    }

    private(set) var launchAtLoginErrorMessage: String?

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

    var mutedProviderIDs: Set<String> {
        didSet {
            defaults.set(Array(mutedProviderIDs), forKey: Keys.mutedProviderIDs)
        }
    }

    var allowsBetaUpdates: Bool {
        didSet { defaults.set(allowsBetaUpdates, forKey: Keys.allowsBetaUpdates) }
    }

    var showBenchmark: Bool {
        didSet { defaults.set(showBenchmark, forKey: Keys.showBenchmark) }
    }

    var benchmarkAPIKey: String {
        get { benchmarkAPIKeyValue }
        set {
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized != benchmarkAPIKeyValue else { return }
            do {
                try BenchmarkAPIKeyStore.save(normalized)
                benchmarkAPIKeyValue = normalized
                benchmarkAPIKeyErrorMessage = nil
            } catch {
                benchmarkAPIKeyErrorMessage = error.localizedDescription
            }
        }
    }

    private(set) var benchmarkAPIKeyErrorMessage: String?

    var launchAtLoginStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func refreshLaunchAtLoginState() {
        let isEnabled = SMAppService.mainApp.status == .enabled
        setLaunchAtLoginValue(isEnabled)
        defaults.set(isEnabled, forKey: Keys.launchAtLogin)
    }

    func isMuted(_ provider: ProviderConfig) -> Bool {
        mutedProviderIDs.contains(provider.id)
    }

    func toggleMute(_ provider: ProviderConfig) {
        if mutedProviderIDs.contains(provider.id) {
            mutedProviderIDs.remove(provider.id)
        } else {
            mutedProviderIDs.insert(provider.id)
        }
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

        if let interval = defaults.object(forKey: Keys.benchmarkRefreshInterval) as? TimeInterval, interval > 0 {
            self.benchmarkRefreshInterval = max(60, interval)
        } else {
            self.benchmarkRefreshInterval = Self.defaultBenchmarkRefreshInterval
        }

        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.launchAtLoginErrorMessage = nil

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
        self.mutedProviderIDs = Set(defaults.stringArray(forKey: Keys.mutedProviderIDs) ?? [])
        self.allowsBetaUpdates = defaults.bool(forKey: Keys.allowsBetaUpdates)
        self.showBenchmark = defaults.object(forKey: Keys.showBenchmark) as? Bool ?? true
        self.benchmarkAPIKeyValue = BenchmarkAPIKeyStore.load() ?? ""
        self.benchmarkAPIKeyErrorMessage = nil
        refreshLaunchAtLoginState()
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

    private func applyLaunchAtLoginChange(requested: Bool, previous: Bool) {
        do {
            if requested {
                try SMAppService.mainApp.register()
                guard SMAppService.mainApp.status == .enabled else {
                    throw LaunchAtLoginError.requiresApproval
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginErrorMessage = nil
            defaults.set(requested, forKey: Keys.launchAtLogin)
        } catch {
            launchAtLoginErrorMessage = error.localizedDescription
            setLaunchAtLoginValue(previous)
            defaults.set(previous, forKey: Keys.launchAtLogin)
        }
    }

    private func setLaunchAtLoginValue(_ value: Bool) {
        guard launchAtLogin != value else { return }
        isApplyingLaunchAtLogin = true
        launchAtLogin = value
        isApplyingLaunchAtLogin = false
    }

    private enum LaunchAtLoginError: LocalizedError {
        case requiresApproval

        var errorDescription: String? {
            switch self {
            case .requiresApproval:
                return "macOS requires approval before MenuStatus can launch at login"
            }
        }
    }

    private enum Keys {
        static let languagePreference = "languagePreference"
        static let refreshInterval = "refreshInterval"
        static let benchmarkRefreshInterval = "benchmarkRefreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviderIDs = "disabledProviderIDs"
        static let iconStyle = "iconStyle"
        static let customProviderNames = "customProviderNames"
        static let providerOrder = "providerOrder"
        static let removedBuiltInIDs = "removedBuiltInIDs"
        static let benchmarkSectionExpanded = "benchmarkSectionExpanded"
        static let groupExpansionOverrides = "groupExpansionOverrides"
        static let mutedProviderIDs = "mutedProviderIDs"
        static let allowsBetaUpdates = UpdaterPreferenceKeys.allowsBetaUpdates
        static let showBenchmark = "showBenchmark"
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
