import Foundation
import Network
import Observation

@MainActor
@Observable
final class StatusStore {
    struct Fetcher {
        let fetchSummary: @Sendable (ProviderConfig) async throws -> StatuspageSummary
        let fetchOfficialHistory: @Sendable (ProviderConfig) async throws -> OfficialHistorySnapshot
        let fetchIncidents: @Sendable (ProviderConfig) async throws -> [Incident]
        let fetchScheduledMaintenances: @Sendable (ProviderConfig) async throws -> [Incident]
        let fetchHistoryPageIncidents: @Sendable (ProviderConfig) async throws -> [HistoryPageIncident]

        static let live = Fetcher(
            fetchSummary: { try await StatusClient.fetchSummary(for: $0) },
            fetchOfficialHistory: { try await StatusClient.fetchOfficialHistory(for: $0) },
            fetchIncidents: { try await StatusClient.fetchIncidents(for: $0) },
            fetchScheduledMaintenances: { try await StatusClient.fetchScheduledMaintenances(for: $0) },
            fetchHistoryPageIncidents: { try await StatusClient.fetchHistoryPageIncidents(for: $0) }
        )
    }

    private struct PersistedStatusProviderEntry: Codable {
        let provider: ProviderConfig
        let summary: StatuspageSummary
        let officialHistory: OfficialHistorySnapshot?
        let incidents: [Incident]
        let maintenances: [Incident]
        let historyPageIncidents: [HistoryPageIncident]
    }

    private struct PersistedStatusSnapshot: Codable {
        let cachedAt: Date
        let lastRefreshed: Date?
        let entries: [PersistedStatusProviderEntry]
    }

    var summaries: [ProviderConfig: StatuspageSummary] = [:]
    var componentTimelines: [ProviderConfig: [String: ComponentTimeline]] = [:]
    var groupedSections: [ProviderConfig: [GroupedComponentSection]] = [:]
    var incidentLookup: [ProviderConfig: [String: [Date: [DayIncidentDetail]]]] = [:]
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?
    private(set) var isConnected = true

    private var pollingTask: Task<Void, Never>?
    private var groupExpansionOverrides: [String: Bool] = [:]
    private var pathMonitor: NWPathMonitor?
    private var debounceTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let now: () -> Date
    let settings: SettingsStore

    init(
        settings: SettingsStore,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.defaults = defaults
        self.now = now
        self.groupExpansionOverrides = settings.groupExpansionOverrides
        restorePersistentSnapshot()
    }

    var overallIndicator: StatusIndicator {
        let indicators = summaries.values.map(\.status.indicator)
        return indicators.max() ?? .none
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        startNetworkMonitor()
        pollingTask = Task {
            while !Task.isCancelled {
                if isConnected {
                    await refreshNow()
                }
                do {
                    try await Task.sleep(for: .seconds(settings.refreshInterval))
                } catch {
                    if Task.isCancelled { break }
                    // Sleep interrupted by network change — loop continues
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        stopNetworkMonitor()
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathChange(connected)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.snowyy.MenuStatus.network"))
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func handlePathChange(_ connected: Bool) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let wasDisconnected = !isConnected
            isConnected = connected
            if connected {
                if wasDisconnected {
                    errorMessage = nil
                    // Cancel the polling sleep to refresh immediately
                    pollingTask?.cancel()
                    pollingTask = Task {
                        while !Task.isCancelled {
                            await refreshNow()
                            do {
                                try await Task.sleep(for: .seconds(settings.refreshInterval))
                            } catch {
                                if Task.isCancelled { break }
                            }
                        }
                    }
                }
            } else {
                errorMessage = nil
            }
        }
    }

    func timeline(for provider: ProviderConfig, componentId: String) -> ComponentTimeline? {
        componentTimelines[provider]?[componentId]
    }

    func sections(for provider: ProviderConfig) -> [GroupedComponentSection] {
        groupedSections[provider] ?? []
    }

    func isExpanded(_ section: GroupedComponentSection, provider: ProviderConfig) -> Bool {
        let key = "\(provider.id):\(section.id)"
        return groupExpansionOverrides[key] ?? (section.status != .operational)
    }

    func toggleExpansion(for section: GroupedComponentSection, provider: ProviderConfig) {
        let key = "\(provider.id):\(section.id)"
        let currentValue = groupExpansionOverrides[key] ?? (section.status != .operational)
        let nextValue = !currentValue
        groupExpansionOverrides[key] = nextValue
        settings.groupExpansionOverrides[key] = nextValue
    }

    func refreshNow() async {
        await refreshNow(fetcher: .live)
    }

    func refreshNow(fetcher: Fetcher) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let activeProviders = settings.providerConfigs
            .enabledProviders(settings: settings)
        let activeSet = Set(activeProviders)
        let existingSummaries = summaries.filter { activeSet.contains($0.key) }

        let fetchResults = await Self.fetchAllProviderData(
            for: activeProviders,
            existingSummaries: existingSummaries,
            fetcher: fetcher
        )

        if !fetchResults.errors.isEmpty {
            errorMessage = fetchResults.errors.joined(separator: "\n")
        }

        let builtIncidentLookup = Self.buildIncidentLookup(
            providers: activeProviders,
            incidents: fetchResults.incidents,
            maintenances: fetchResults.maintenances,
            historyPageIncidents: fetchResults.historyPageIncidents,
            officialHistories: fetchResults.officialHistories,
            summaries: fetchResults.summaries
        )

        let derivedState = Self.derivePresentationState(
            providers: activeProviders,
            summaries: fetchResults.summaries,
            currentTimelines: componentTimelines.filter { activeSet.contains($0.key) },
            currentSections: groupedSections.filter { activeSet.contains($0.key) },
            officialHistories: fetchResults.officialHistories,
            incidentLookup: builtIncidentLookup
        )

        summaries = fetchResults.summaries
        componentTimelines = derivedState.timelines
        groupedSections = derivedState.sections
        incidentLookup = builtIncidentLookup
        lastRefreshed = now()
        persistSnapshot(
            summaries: fetchResults.summaries,
            officialHistories: fetchResults.officialHistories,
            incidents: fetchResults.incidents,
            maintenances: fetchResults.maintenances,
            historyPageIncidents: fetchResults.historyPageIncidents
        )
        isLoading = false
    }

    private struct ProviderFetchResults {
        var summaries: [ProviderConfig: StatuspageSummary]
        var officialHistories: [ProviderConfig: OfficialHistorySnapshot] = [:]
        var incidents: [ProviderConfig: [Incident]] = [:]
        var maintenances: [ProviderConfig: [Incident]] = [:]
        var historyPageIncidents: [ProviderConfig: [HistoryPageIncident]] = [:]
        var errors: [String] = []
    }

    nonisolated private static func fetchAllProviderData(
        for providers: [ProviderConfig],
        existingSummaries: [ProviderConfig: StatuspageSummary],
        fetcher: Fetcher
    ) async -> ProviderFetchResults {
        enum FetchResult {
            case summary(ProviderConfig, Result<StatuspageSummary, Error>)
            case officialHistory(ProviderConfig, Result<OfficialHistorySnapshot, Error>)
            case incidents(ProviderConfig, Result<[Incident], Error>)
            case maintenances(ProviderConfig, Result<[Incident], Error>)
            case historyPage(ProviderConfig, Result<[HistoryPageIncident], Error>)
        }

        var results = ProviderFetchResults(summaries: existingSummaries)

        await withTaskGroup(of: FetchResult.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let summary = try await fetcher.fetchSummary(provider)
                        return .summary(provider, .success(summary))
                    } catch {
                        return .summary(provider, .failure(error))
                    }
                }

                group.addTask {
                    do {
                        let history = try await fetcher.fetchOfficialHistory(provider)
                        return .officialHistory(provider, .success(history))
                    } catch {
                        return .officialHistory(provider, .failure(error))
                    }
                }

                group.addTask {
                    do {
                        let incidents = try await fetcher.fetchIncidents(provider)
                        return .incidents(provider, .success(incidents))
                    } catch {
                        return .incidents(provider, .failure(error))
                    }
                }

                if provider.platform == .atlassianStatuspage {
                    group.addTask {
                        do {
                            let maintenances = try await fetcher.fetchScheduledMaintenances(provider)
                            return .maintenances(provider, .success(maintenances))
                        } catch {
                            return .maintenances(provider, .failure(error))
                        }
                    }

                    group.addTask {
                        do {
                            let historyIncidents = try await fetcher.fetchHistoryPageIncidents(provider)
                            return .historyPage(provider, .success(historyIncidents))
                        } catch {
                            return .historyPage(provider, .failure(error))
                        }
                    }
                }
            }

            for await result in group {
                switch result {
                case .summary(let provider, .success(let summary)):
                    results.summaries[provider] = summary
                case .summary(let provider, .failure(let error)):
                    results.errors.append("\(provider.displayName): \(error.localizedDescription)")
                case .officialHistory(let provider, .success(let history)):
                    results.officialHistories[provider] = history
                case .officialHistory(_, .failure):
                    break
                case .incidents(let provider, .success(let incidents)):
                    results.incidents[provider] = incidents
                case .incidents(_, .failure):
                    break
                case .maintenances(let provider, .success(let maintenances)):
                    results.maintenances[provider] = maintenances
                case .maintenances(_, .failure):
                    break
                case .historyPage(let provider, .success(let historyIncidents)):
                    results.historyPageIncidents[provider] = historyIncidents
                case .historyPage(_, .failure):
                    break
                }
            }
        }

        return results
    }

    private enum PersistentCache {
        static let defaultsKey = "statusRawSnapshotCache"
        static let ttl: TimeInterval = 300
    }

    private func restorePersistentSnapshot() {
        guard let providerConfigs = settings.providerConfigs else { return }
        guard
            let data = defaults.data(forKey: PersistentCache.defaultsKey),
            let snapshot = try? JSONDecoder().decode(PersistedStatusSnapshot.self, from: data)
        else {
            defaults.removeObject(forKey: PersistentCache.defaultsKey)
            return
        }

        guard snapshot.cachedAt >= now().addingTimeInterval(-PersistentCache.ttl) else {
            defaults.removeObject(forKey: PersistentCache.defaultsKey)
            return
        }

        let activeProviders = providerConfigs.enabledProviders(settings: settings)
        let activeSet = Set(activeProviders)
        let entries = snapshot.entries.filter { activeSet.contains($0.provider) }
        guard !entries.isEmpty else { return }

        let summaries = Dictionary(entries.map { ($0.provider, $0.summary) }, uniquingKeysWith: { _, new in new })
        let officialHistories = Dictionary(
            entries.compactMap { entry in
                entry.officialHistory.map { (entry.provider, $0) }
            },
            uniquingKeysWith: { _, new in new }
        )
        let incidents = Dictionary(entries.map { ($0.provider, $0.incidents) }, uniquingKeysWith: { _, new in new })
        let maintenances = Dictionary(entries.map { ($0.provider, $0.maintenances) }, uniquingKeysWith: { _, new in new })
        let historyPageIncidents = Dictionary(
            entries.map { ($0.provider, $0.historyPageIncidents) },
            uniquingKeysWith: { _, new in new }
        )

        let builtIncidentLookup = Self.buildIncidentLookup(
            providers: activeProviders,
            incidents: incidents,
            maintenances: maintenances,
            historyPageIncidents: historyPageIncidents,
            officialHistories: officialHistories,
            summaries: summaries
        )

        let derivedState = Self.derivePresentationState(
            providers: activeProviders,
            summaries: summaries,
            currentTimelines: [:],
            currentSections: [:],
            officialHistories: officialHistories,
            incidentLookup: builtIncidentLookup
        )

        self.summaries = summaries
        self.componentTimelines = derivedState.timelines
        self.groupedSections = derivedState.sections
        self.incidentLookup = builtIncidentLookup
        self.lastRefreshed = snapshot.lastRefreshed
    }

    private func persistSnapshot(
        summaries: [ProviderConfig: StatuspageSummary],
        officialHistories: [ProviderConfig: OfficialHistorySnapshot],
        incidents: [ProviderConfig: [Incident]],
        maintenances: [ProviderConfig: [Incident]],
        historyPageIncidents: [ProviderConfig: [HistoryPageIncident]]
    ) {
        let entries = summaries.keys.sorted { $0.id < $1.id }.map { provider in
            PersistedStatusProviderEntry(
                provider: provider,
                summary: summaries[provider]!,
                officialHistory: officialHistories[provider],
                incidents: incidents[provider] ?? [],
                maintenances: maintenances[provider] ?? [],
                historyPageIncidents: historyPageIncidents[provider] ?? []
            )
        }

        guard !entries.isEmpty else {
            defaults.removeObject(forKey: PersistentCache.defaultsKey)
            return
        }

        let snapshot = PersistedStatusSnapshot(
            cachedAt: now(),
            lastRefreshed: lastRefreshed,
            entries: entries
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: PersistentCache.defaultsKey)
    }

    func dayDetails(for provider: ProviderConfig, componentId: String) -> [Date: [DayIncidentDetail]] {
        incidentLookup[provider]?[componentId] ?? [:]
    }

    func dayDetails(for provider: ProviderConfig, section: GroupedComponentSection) -> [Date: [DayIncidentDetail]] {
        var merged: [Date: [DayIncidentDetail]] = [:]
        for component in section.components {
            if let componentDetails = incidentLookup[provider]?[component.id] {
                for (date, details) in componentDetails {
                    merged[date, default: []].append(contentsOf: details)
                }
            }
        }
        return merged
    }
}

// MARK: - Incident Lookup

extension StatusStore {
    nonisolated static func buildIncidentLookup(
        providers: [ProviderConfig],
        incidents: [ProviderConfig: [Incident]],
        maintenances: [ProviderConfig: [Incident]] = [:],
        historyPageIncidents: [ProviderConfig: [HistoryPageIncident]] = [:],
        officialHistories: [ProviderConfig: OfficialHistorySnapshot],
        summaries: [ProviderConfig: StatuspageSummary]
    ) -> [ProviderConfig: [String: [Date: [DayIncidentDetail]]]] {
        var result: [ProviderConfig: [String: [Date: [DayIncidentDetail]]]] = [:]

        for provider in providers {
            let timeZone = summaries[provider]?.page.timeZone
            var calendar = Calendar(identifier: .gregorian)
            if let tz = timeZone, let zone = TimeZone(identifier: tz) {
                calendar.timeZone = zone
            }

            var lookup: [String: [Date: [DayIncidentDetail]]] = [:]
            let allComponentIDs = Set(
                (summaries[provider]?.components ?? [])
                    .filter { $0.group != true }
                    .map(\.id)
            )

            // From incidents API (Atlassian Statuspage — has affected_components)
            var processedIncidentIDs = Set<String>()
            if provider.platform == .atlassianStatuspage {
                let combined = (incidents[provider] ?? []) + (maintenances[provider] ?? [])
                for incident in combined {
                    guard let startedAtStr = incident.startedAt,
                          let startedAt = DateParsing.parseISODate(startedAtStr) else { continue }
                    let resolvedAt = incident.resolvedAt.flatMap { DateParsing.parseISODate($0) } ?? Date()

                    processedIncidentIDs.insert(incident.id)

                    let fromUpdates = (incident.incidentUpdates ?? [])
                        .flatMap { $0.affectedComponents ?? [] }
                        .map(\.code)
                    let fromComponents = (incident.components ?? []).map(\.id)
                    let explicitIDs = Set(fromUpdates + fromComponents)
                    // If no component association, associate to all (bar color filtering prevents false triggers)
                    let componentIDs = explicitIDs.isEmpty ? allComponentIDs : explicitIDs

                    let impactLevel: TimelineDayLevel = switch incident.impact {
                    case .minor: .degraded
                    case .major: .partialOutage
                    case .critical: .majorOutage
                    case .maintenance: .maintenance
                    default: .degraded
                    }

                    appendDayDetails(
                        &lookup, componentIDs: componentIDs,
                        startedAt: startedAt, resolvedAt: resolvedAt,
                        level: impactLevel, incidentName: incident.name,
                        calendar: calendar
                    )
                }

                // Supplement with /history page incidents (no component info — associate to all)
                if let historyIncidents = historyPageIncidents[provider] {
                    for incident in historyIncidents {
                        guard !processedIncidentIDs.contains(incident.code) else { continue }

                        let impactLevel: TimelineDayLevel = switch incident.impact {
                        case .minor: .degraded
                        case .major: .partialOutage
                        case .critical: .majorOutage
                        case .maintenance: .maintenance
                        default: .degraded
                        }

                        appendDayDetails(
                            &lookup, componentIDs: allComponentIDs,
                            startedAt: incident.startedAt, resolvedAt: incident.resolvedAt,
                            level: impactLevel, incidentName: incident.name,
                            calendar: calendar
                        )
                    }
                }
            }

            // From official history impacts (incident.io — has component-level impacts + incident names)
            if provider.platform == .incidentIO, let history = officialHistories[provider] {
                for (componentId, component) in history.componentsByID {
                    for impact in component.impacts {
                        guard let startAt = DateParsing.parseISODate(impact.startAt) else { continue }
                        let endAt = impact.endAt.flatMap { DateParsing.parseISODate($0) } ?? Date()
                        let incidentName = impact.statusPageIncidentId.flatMap { history.incidentNames[$0] }

                        appendDayDetails(
                            &lookup, componentIDs: [componentId],
                            startedAt: startAt, resolvedAt: endAt,
                            level: impact.timelineLevel, incidentName: incidentName,
                            calendar: calendar
                        )
                    }
                }
            }

            if !lookup.isEmpty {
                result[provider] = lookup
            }
        }

        return result
    }

    nonisolated private static func appendDayDetails(
        _ lookup: inout [String: [Date: [DayIncidentDetail]]],
        componentIDs: Set<String>,
        startedAt: Date, resolvedAt: Date,
        level: TimelineDayLevel, incidentName: String?,
        calendar: Calendar
    ) {
        let startDay = calendar.startOfDay(for: startedAt)
        let endDay = calendar.startOfDay(for: resolvedAt)
        var day = startDay

        while day <= endDay {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            let effectiveStart = max(startedAt, day)
            let effectiveEnd = min(resolvedAt, dayEnd)
            let duration = effectiveEnd.timeIntervalSince(effectiveStart)

            for componentId in componentIDs {
                let detail = DayIncidentDetail(
                    level: level,
                    durationSeconds: max(0, duration),
                    incidentName: incidentName
                )
                lookup[componentId, default: [:]][day, default: []].append(detail)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }
}

// MARK: - Presentation Derivation

extension StatusStore {
    nonisolated static func derivePresentationState(
        providers: [ProviderConfig],
        summaries: [ProviderConfig: StatuspageSummary],
        currentTimelines: [ProviderConfig: [String: ComponentTimeline]],
        currentSections: [ProviderConfig: [GroupedComponentSection]],
        officialHistories: [ProviderConfig: OfficialHistorySnapshot],
        incidentLookup: [ProviderConfig: [String: [Date: [DayIncidentDetail]]]] = [:]
    ) -> (
        timelines: [ProviderConfig: [String: ComponentTimeline]],
        sections: [ProviderConfig: [GroupedComponentSection]]
    ) {
        var nextTimelines = currentTimelines
        var nextSections = currentSections

        for provider in providers {
            guard let summary = summaries[provider] else { continue }

            guard let officialHistory = officialHistories[provider] else {
                nextTimelines[provider] = currentTimelines[provider] ?? [:]
                continue
            }

            let providerIncidents = incidentLookup[provider] ?? [:]

            if !officialHistory.groups.isEmpty {
                let projection = buildGroupedSections(
                    snapshot: officialHistory,
                    currentSummary: summary
                )
                nextTimelines[provider] = projection.timelines
                nextSections[provider] = projection.sections
            } else if summary.components.contains(where: { $0.group == true }) {
                let projection = buildGroupedSectionsFromSummary(
                    snapshot: officialHistory,
                    summary: summary,
                    incidentLookup: providerIncidents
                )
                nextTimelines[provider] = projection.timelines
                nextSections[provider] = projection.sections
            } else {
                nextTimelines[provider] = buildFlatTimelines(
                    snapshot: officialHistory,
                    summary: summary,
                    incidentLookup: providerIncidents
                )
                nextSections[provider] = []
            }
        }

        return (nextTimelines, nextSections)
    }

    nonisolated static func buildFlatTimelines(
        snapshot: OfficialHistorySnapshot,
        summary: StatuspageSummary,
        incidentLookup: [String: [Date: [DayIncidentDetail]]] = [:]
    ) -> [String: ComponentTimeline] {
        let now = snapshot.generatedAt ?? Date()
        var timelines: [String: ComponentTimeline] = [:]

        for component in summary.components where component.group != true {
            if let officialComponent = snapshot.componentsByID[component.id] {
                timelines[component.id] = ComponentTimeline.build(
                    from: officialComponent,
                    now: now,
                    timeZoneIdentifier: summary.page.timeZone
                )
            } else if let dayDetails = incidentLookup[component.id] {
                timelines[component.id] = ComponentTimeline.buildEstimated(
                    from: dayDetails,
                    title: component.name,
                    now: now,
                    timeZoneIdentifier: summary.page.timeZone
                )
            } else {
                timelines[component.id] = ComponentTimeline.buildUnavailable(
                    title: component.name,
                    now: now,
                    timeZoneIdentifier: summary.page.timeZone
                )
            }
        }

        return timelines
    }

    nonisolated static func buildGroupedSections(
        snapshot: OfficialHistorySnapshot,
        currentSummary: StatuspageSummary
    ) -> (sections: [GroupedComponentSection], timelines: [String: ComponentTimeline]) {
        let now = snapshot.generatedAt ?? Date()
        let summaryStatuses = Dictionary(
            currentSummary.components.map { ($0.id, $0.status) },
            uniquingKeysWith: { _, new in new }
        )

        var timelines: [String: ComponentTimeline] = [:]
        let sections = snapshot.groups.compactMap { group -> GroupedComponentSection? in
            guard !group.hidden else { return nil }

            let components = group.componentIDs.compactMap { componentID -> Component? in
                guard let officialComponent = snapshot.componentsByID[componentID],
                      !officialComponent.hidden,
                      officialComponent.displayUptime else {
                    return nil
                }

                let currentImpactStatus = currentOfficialStatus(
                    impacts: officialComponent.impacts,
                    now: now
                )
                let currentStatus = max(
                    summaryStatuses[componentID] ?? .operational,
                    currentImpactStatus
                )

                timelines[componentID] = ComponentTimeline.build(
                    from: officialComponent,
                    now: now,
                    timeZoneIdentifier: currentSummary.page.timeZone
                )

                return Component(
                    id: componentID,
                    name: officialComponent.name,
                    status: currentStatus,
                    position: nil,
                    description: nil,
                    startDate: officialComponent.dataAvailableSince,
                    groupId: group.id,
                    group: false,
                    onlyShowIfDegraded: nil
                )
            }

            guard !components.isEmpty else { return nil }

            let groupStatus = components.map(\.status).max() ?? .operational
            let groupTimelines = components.compactMap { timelines[$0.id] }

            return GroupedComponentSection(
                id: group.id,
                title: group.name,
                components: components,
                status: groupStatus,
                timeline: ComponentTimeline.aggregate(
                    groupTimelines,
                    title: group.name,
                    uptimePercentOverride: group.uptimePercent
                )
            )
        }

        return (sections, timelines)
    }

    nonisolated static func buildGroupedSectionsFromSummary(
        snapshot: OfficialHistorySnapshot,
        summary: StatuspageSummary,
        incidentLookup: [String: [Date: [DayIncidentDetail]]] = [:]
    ) -> (sections: [GroupedComponentSection], timelines: [String: ComponentTimeline]) {
        let now = snapshot.generatedAt ?? Date()
        let groupComponents = summary.components.filter { $0.group == true }

        var timelines: [String: ComponentTimeline] = [:]
        let sections = groupComponents.compactMap { groupComp -> GroupedComponentSection? in
            let children = summary.components.filter {
                $0.groupId == groupComp.id && $0.group != true
                    && $0.onlyShowIfDegraded != true
            }
            guard !children.isEmpty else { return nil }

            for child in children {
                if let officialComp = snapshot.componentsByID[child.id] {
                    timelines[child.id] = ComponentTimeline.build(
                        from: officialComp, now: now,
                        timeZoneIdentifier: summary.page.timeZone
                    )
                } else if let dayDetails = incidentLookup[child.id] {
                    timelines[child.id] = ComponentTimeline.buildEstimated(
                        from: dayDetails,
                        title: child.name,
                        now: now,
                        timeZoneIdentifier: summary.page.timeZone
                    )
                }
            }

            let groupStatus = children.map(\.status).max() ?? .operational
            let childTimelines = children.compactMap { timelines[$0.id] }

            return GroupedComponentSection(
                id: groupComp.id,
                title: groupComp.name,
                components: children,
                status: groupStatus,
                timeline: ComponentTimeline.aggregate(childTimelines, title: groupComp.name)
            )
        }

        return (sections, timelines)
    }

    nonisolated static func currentOfficialStatus(impacts: [OfficialComponentImpact], now: Date) -> ComponentStatus {
        impacts
            .filter { $0.isActive(at: now) }
            .map(\.componentStatus)
            .max() ?? .operational
    }
}
