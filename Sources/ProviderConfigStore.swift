import Foundation
import Observation

@Observable
final class ProviderConfigStore {
    private(set) var providers: [ProviderConfig] = ProviderConfig.builtInProviders
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MenuStatus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("providers.json")
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

    func removeProvider(id: String) {
        guard providers.first(where: { $0.id == id })?.isBuiltIn != true else { return }
        providers.removeAll { $0.id == id }
        saveToDisk()
    }

    // MARK: - Auto-detect

    static func detect(url: URL) async throws -> ProviderConfig {
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

    private static func detectPlatform(url: URL) async throws -> StatusPlatform {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            return .atlassianStatuspage
        }
        return html.contains("__next_f.push") ? .incidentIO : .atlassianStatuspage
    }

    // MARK: - Import / Export

    struct ExportFormat: Codable {
        let providers: [ExportEntry]
    }

    struct ExportEntry: Codable {
        let name: String
        let url: String
        let platform: StatusPlatform?
    }

    func exportJSON() throws -> Data {
        let entries = providers.filter { !$0.isBuiltIn }.map {
            ExportEntry(name: $0.displayName, url: $0.baseURL.absoluteString, platform: $0.platform)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ExportFormat(providers: entries))
    }

    func importJSON(_ data: Data) async throws -> [ProviderConfig] {
        let decoded = try JSONDecoder().decode(ExportFormat.self, from: data)
        var added: [ProviderConfig] = []

        for entry in decoded.providers {
            guard let url = URL(string: entry.url) else { continue }
            let config: ProviderConfig
            if let platform = entry.platform {
                config = ProviderConfig(
                    id: url.host ?? entry.name.lowercased(),
                    displayName: entry.name,
                    baseURL: url, platform: platform, isBuiltIn: false
                )
            } else {
                config = try await Self.detect(url: url)
            }
            if !providers.contains(where: { $0.id == config.id }) {
                providers.append(config)
                added.append(config)
            }
        }

        if !added.isEmpty { saveToDisk() }
        return added
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
