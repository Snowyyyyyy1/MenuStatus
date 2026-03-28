import Foundation
import Observation

@Observable
final class StatusStore {
    var summaries: [ProviderConfig: StatuspageSummary] = [:]
    var componentTimelines: [ProviderConfig: [String: ComponentTimeline]] = [:]
    var groupedSections: [ProviderConfig: [GroupedComponentSection]] = [:]
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var groupExpansionOverrides: [String: Bool] = [:]
    let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var overallIndicator: StatusIndicator {
        let indicators = summaries.values.map(\.status.indicator)
        return indicators.max() ?? .none
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshNow()
                do {
                    try await Task.sleep(for: .seconds(settings.refreshInterval))
                } catch {
                    break
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func timeline(for provider: ProviderConfig, componentId: String) -> ComponentTimeline? {
        componentTimelines[provider]?[componentId]
    }

    func sections(for provider: ProviderConfig) -> [GroupedComponentSection] {
        groupedSections[provider] ?? []
    }

    func isExpanded(_ section: GroupedComponentSection) -> Bool {
        groupExpansionOverrides[section.id] ?? (section.status != .operational)
    }

    func toggleExpansion(for section: GroupedComponentSection) {
        let currentValue = isExpanded(section)
        groupExpansionOverrides[section.id] = !currentValue
    }

    @MainActor
    func refreshNow() async {
        isLoading = true
        errorMessage = nil

        let activeProviders = settings.providerConfigs.enabledProviders(settings: settings)
        let activeSet = Set(activeProviders)
        var stagedSummaries = summaries.filter { activeSet.contains($0.key) }

        enum FetchResult {
            case summary(ProviderConfig, Result<StatuspageSummary, Error>)
            case officialHistory(ProviderConfig, Result<OfficialHistorySnapshot, Error>)
        }

        await withTaskGroup(of: FetchResult.self) { group in
            for provider in activeProviders {
                group.addTask {
                    do {
                        let summary = try await StatusClient.fetchSummary(for: provider)
                        return .summary(provider, .success(summary))
                    } catch {
                        return .summary(provider, .failure(error))
                    }
                }

                group.addTask {
                    do {
                        let history = try await StatusClient.fetchOfficialHistory(for: provider)
                        return .officialHistory(provider, .success(history))
                    } catch {
                        return .officialHistory(provider, .failure(error))
                    }
                }
            }

            var errors: [String] = []
            var officialHistories: [ProviderConfig: OfficialHistorySnapshot] = [:]
            for await result in group {
                switch result {
                case .summary(let provider, .success(let summary)):
                    stagedSummaries[provider] = summary
                case .summary(let provider, .failure(let error)):
                    errors.append("\(provider.displayName): \(error.localizedDescription)")
                case .officialHistory(let provider, .success(let history)):
                    officialHistories[provider] = history
                case .officialHistory(_, .failure):
                    break
                }
            }

            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
            }

            let derivedState = Self.derivePresentationState(
                providers: activeProviders,
                summaries: stagedSummaries,
                currentTimelines: componentTimelines.filter { activeSet.contains($0.key) },
                currentSections: groupedSections.filter { activeSet.contains($0.key) },
                officialHistories: officialHistories
            )

            summaries = stagedSummaries
            componentTimelines = derivedState.timelines
            groupedSections = derivedState.sections
        }

        lastRefreshed = Date()
        isLoading = false
    }
}

// MARK: - Presentation Derivation

extension StatusStore {
    static func derivePresentationState(
        providers: [ProviderConfig],
        summaries: [ProviderConfig: StatuspageSummary],
        currentTimelines: [ProviderConfig: [String: ComponentTimeline]],
        currentSections: [ProviderConfig: [GroupedComponentSection]],
        officialHistories: [ProviderConfig: OfficialHistorySnapshot]
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
                    summary: summary
                )
                nextTimelines[provider] = projection.timelines
                nextSections[provider] = projection.sections
            } else {
                nextTimelines[provider] = buildFlatTimelines(
                    snapshot: officialHistory,
                    summary: summary
                )
                nextSections[provider] = []
            }
        }

        return (nextTimelines, nextSections)
    }

    static func buildFlatTimelines(
        snapshot: OfficialHistorySnapshot,
        summary: StatuspageSummary
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

    static func buildGroupedSections(
        snapshot: OfficialHistorySnapshot,
        currentSummary: StatuspageSummary
    ) -> (sections: [GroupedComponentSection], timelines: [String: ComponentTimeline]) {
        let now = snapshot.generatedAt ?? Date()
        let summaryStatuses = Dictionary(uniqueKeysWithValues: currentSummary.components.map { ($0.id, $0.status) })

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

    static func buildGroupedSectionsFromSummary(
        snapshot: OfficialHistorySnapshot,
        summary: StatuspageSummary
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
                } else {
                    timelines[child.id] = ComponentTimeline.buildUnavailable(
                        title: child.name, now: now,
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

    static func currentOfficialStatus(impacts: [OfficialComponentImpact], now: Date) -> ComponentStatus {
        impacts
            .filter { $0.isActive(at: now) }
            .map(\.componentStatus)
            .max() ?? .operational
    }
}
