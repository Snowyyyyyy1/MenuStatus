import Foundation

protocol StatusProviderAdapter {
    func fetchSummary(for provider: ProviderConfig) async throws -> StatuspageSummary
    func fetchOfficialHistory(for provider: ProviderConfig) async throws -> OfficialHistorySnapshot
    func fetchIncidents(for provider: ProviderConfig) async throws -> [Incident]
    func fetchScheduledMaintenances(for provider: ProviderConfig) async throws -> [Incident]
    func fetchHistoryPageIncidents(for provider: ProviderConfig) async throws -> [HistoryPageIncident]
}

extension StatusProviderAdapter {
    func fetchSummaryAPI(for provider: ProviderConfig) async throws -> StatuspageSummary {
        let data = try await StatusClient.fetchData(from: provider.apiURL)
        return try StatusClient.decoder.decode(StatuspageSummary.self, from: data)
    }

    func fetchStatuspageIncidentsAPI(for provider: ProviderConfig) async throws -> [Incident] {
        var components = URLComponents(
            url: provider.baseURL.appendingPathComponent("api/v2/incidents.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = components.url else {
            throw StatusClientTransportError.invalidResponse(provider.baseURL)
        }
        let data = try await StatusClient.fetchData(from: url)
        let response = try StatusClient.decoder.decode(IncidentHistoryResponse.self, from: data)
        return response.incidents
    }

    func fetchStatuspageMaintenancesAPI(for provider: ProviderConfig) async throws -> [Incident] {
        let url = provider.baseURL.appendingPathComponent("api/v2/scheduled-maintenances.json")
        let data = try await StatusClient.fetchData(from: url)
        let response = try StatusClient.decoder.decode(ScheduledMaintenancesResponse.self, from: data)
        return response.scheduledMaintenances
    }

    func fetchHistoryPageIncidents(for provider: ProviderConfig) async throws -> [HistoryPageIncident] {
        []
    }
}

struct AtlassianStatuspageProviderAdapter: StatusProviderAdapter {
    func fetchSummary(for provider: ProviderConfig) async throws -> StatuspageSummary {
        try await fetchSummaryAPI(for: provider)
    }

    func fetchOfficialHistory(for provider: ProviderConfig) async throws -> OfficialHistorySnapshot {
        let data = try await StatusClient.fetchData(from: provider.statusPageURL)
        return try StatusClient.parseAtlassianStatuspageHistoryHTML(data)
    }

    func fetchIncidents(for provider: ProviderConfig) async throws -> [Incident] {
        try await fetchStatuspageIncidentsAPI(for: provider)
    }

    func fetchScheduledMaintenances(for provider: ProviderConfig) async throws -> [Incident] {
        try await fetchStatuspageMaintenancesAPI(for: provider)
    }

    func fetchHistoryPageIncidents(for provider: ProviderConfig) async throws -> [HistoryPageIncident] {
        let data = try await StatusClient.fetchData(from: provider.statusPageURL.appendingPathComponent("history"))
        return StatusClient.parseAtlassianHistoryPage(data)
    }
}

struct IncidentIOStatusProviderAdapter: StatusProviderAdapter {
    func fetchSummary(for provider: ProviderConfig) async throws -> StatuspageSummary {
        try await fetchSummaryAPI(for: provider)
    }

    func fetchOfficialHistory(for provider: ProviderConfig) async throws -> OfficialHistorySnapshot {
        async let mainFetch = StatusClient.fetchData(from: provider.statusPageURL)
        async let historyFetch: Data? = try? await StatusClient.fetchData(
            from: provider.statusPageURL.appendingPathComponent("history")
        )

        var snapshot = try StatusClient.parseIncidentIOHistoryHTML(try await mainFetch)
        if let historyData = await historyFetch,
           let names = try? StatusClient.parseIncidentIOIncidentNames(historyData) {
            snapshot = OfficialHistorySnapshot(
                generatedAt: snapshot.generatedAt,
                groups: snapshot.groups,
                componentsByID: snapshot.componentsByID,
                incidentNames: names
            )
        }
        return snapshot
    }

    func fetchIncidents(for provider: ProviderConfig) async throws -> [Incident] {
        try await fetchStatuspageIncidentsAPI(for: provider)
    }

    func fetchScheduledMaintenances(for provider: ProviderConfig) async throws -> [Incident] {
        try await fetchStatuspageMaintenancesAPI(for: provider)
    }
}

struct FlashdutyStatusProviderAdapter: StatusProviderAdapter {
    func fetchSummary(for provider: ProviderConfig) async throws -> StatuspageSummary {
        let data = try await StatusClient.fetchData(from: provider.apiURL)
        return try StatusClient.parseFlashdutySummaryHTML(data, sourceURL: provider.baseURL)
    }

    func fetchOfficialHistory(for provider: ProviderConfig) async throws -> OfficialHistorySnapshot {
        let data = try await StatusClient.fetchData(from: provider.statusPageURL)
        return try StatusClient.parseFlashdutyHistoryHTML(data)
    }

    func fetchIncidents(for provider: ProviderConfig) async throws -> [Incident] {
        []
    }

    func fetchScheduledMaintenances(for provider: ProviderConfig) async throws -> [Incident] {
        []
    }
}
