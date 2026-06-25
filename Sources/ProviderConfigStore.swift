import Foundation
import Observation

@MainActor @Observable
final class ProviderConfigStore {
    private(set) var providers: [ProviderConfig]
    private let fileURL: URL

    init(removedBuiltInIDs: Set<String> = [], fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("MenuStatus", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("providers.json")
        }
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
        // Clear the remaining per-provider state keyed by id. Without this, an alias /
        // mute / group-expansion override is resurrected when the same status page is
        // re-added later (detect() reuses the server-assigned page id), and these
        // UserDefaults dictionaries accumulate dead keys over time.
        settings.customProviderNames.removeValue(forKey: id)
        settings.mutedProviderIDs.remove(id)
        let expansionPrefix = "\(id):"
        settings.groupExpansionOverrides = settings.groupExpansionOverrides.filter {
            !$0.key.hasPrefix(expansionPrefix)
        }

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

    nonisolated static func detect(url: URL, session: URLSession = StatusClient.session) async throws -> ProviderConfig {
        let apiURL = url.appendingPathComponent("api/v2/summary.json")
        let data: Data
        do {
            let (summaryData, response) = try await session.data(from: apiURL)
            try StatusClient.validateHTTPResponse(response, for: apiURL)
            data = summaryData
        } catch let transportError as StatusClientTransportError {
            guard case .unsuccessfulStatusCode(_, 404) = transportError else {
                throw transportError
            }

            do {
                let (rootData, rootResponse) = try await session.data(from: url)
                try StatusClient.validateHTTPResponse(rootResponse, for: url)
                if try detectPlatform(in: rootData) == .flashduty {
                    let page = try StatusClient.parseFlashdutyPageConfig(rootData)
                    return ProviderConfig(
                        id: String(page.pageId), displayName: page.name,
                        baseURL: url, platform: .flashduty, isBuiltIn: false
                    )
                }
            } catch {
                throw transportError
            }
            throw transportError
        } catch {
            throw error
        }
        let summary = try StatusClient.decoder.decode(StatuspageSummary.self, from: data)
        let platform = (try? await detectPlatform(url: url, session: session)) ?? .atlassianStatuspage

        return ProviderConfig(
            id: summary.page.id, displayName: summary.page.name,
            baseURL: url, platform: platform, isBuiltIn: false
        )
    }

    nonisolated static func detectPlatform(url: URL, session: URLSession = StatusClient.session) async throws -> StatusPlatform {
        let (data, response) = try await session.data(from: url)
        try StatusClient.validateHTTPResponse(response, for: url)
        return try detectPlatform(in: data)
    }

    nonisolated private static func detectPlatform(in data: Data) throws -> StatusPlatform {
        guard let html = String(data: data, encoding: .utf8) else {
            return .atlassianStatuspage
        }
        if html.contains("initialPageConfig")
            && (html.contains("page_id") || html.contains("component_id")) {
            return .flashduty
        }
        return html.contains("__next_f.push") ? .incidentIO : .atlassianStatuspage
    }

    // MARK: - Persistence

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private func saveToDisk() {
        let custom = providers.filter { !$0.isBuiltIn }
        guard let data = try? Self.encoder.encode(custom) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let custom = try? Self.decoder.decode([ProviderConfig].self, from: data) else {
            return
        }
        for config in custom where !providers.contains(where: { $0.id == config.id }) {
            providers.append(config)
        }
    }
}
