import Foundation
import Observation

@MainActor @Observable
final class ProviderConfigStore {
    private(set) var providers: [ProviderConfig]
    private let fileURL: URL

    init(removedBuiltInIDs: Set<String> = []) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MenuStatus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("providers.json")
        self.providers = ProviderConfig.builtInProviders.filter { !removedBuiltInIDs.contains($0.id) }
        loadFromDisk()
    }

    var allProviders: [ProviderConfig] { providers }

    func provider(for id: String) -> ProviderConfig? {
        providers.first { $0.id == id }
    }

    func addProvider(_ config: ProviderConfig) {
        guard !providers.contains(where: { $0.id == config.id }) else { return }
        providers.append(config)
        saveToDisk()
    }

    func removeProvider(id: String, settings: SettingsStore) {
        guard let provider = providers.first(where: { $0.id == id }) else { return }
        let enabledCount = providers.filter { settings.isEnabled($0) }.count
        let isEnabled = !settings.disabledProviderIDs.contains(id)
        guard !isEnabled || enabledCount > 1 else { return }

        providers.removeAll { $0.id == id }
        settings.disabledProviderIDs.remove(id)
        settings.providerOrder.removeAll { $0 == id }

        if provider.isBuiltIn {
            settings.removedBuiltInIDs.insert(id)
        } else {
            saveToDisk()
        }
    }

    func resetBuiltInProviders(settings: SettingsStore) {
        settings.removedBuiltInIDs.removeAll()
        for builtIn in ProviderConfig.builtInProviders where !providers.contains(where: { $0.id == builtIn.id }) {
            providers.append(builtIn)
        }
    }

    // MARK: - Auto-detect

    nonisolated static func detect(url: URL) async throws -> ProviderConfig {
        let apiURL = url.appendingPathComponent("api/v2/summary.json")
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        try StatusClient.validateHTTPResponse(response, for: apiURL)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(StatuspageSummary.self, from: data)

        let platform = try await detectPlatform(url: url)
        let id = summary.page.id
        let name = summary.page.name

        return ProviderConfig(
            id: id, displayName: name,
            baseURL: url, platform: platform, isBuiltIn: false
        )
    }

    nonisolated private static func detectPlatform(url: URL) async throws -> StatusPlatform {
        let (data, response) = try await URLSession.shared.data(from: url)
        try StatusClient.validateHTTPResponse(response, for: url)
        guard let html = String(data: data, encoding: .utf8) else {
            return .atlassianStatuspage
        }
        return html.contains("__next_f.push") ? .incidentIO : .atlassianStatuspage
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let custom = providers.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let custom = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
            return
        }
        for config in custom where !providers.contains(where: { $0.id == config.id }) {
            providers.append(config)
        }
    }
}
