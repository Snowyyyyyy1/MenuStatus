import Foundation
import Observation

@Observable
final class StatusStore {
    var summaries: [Provider: StatuspageSummary] = [:]
    var componentTimelines: [Provider: [String: ComponentTimeline]] = [:]
    var groupedSections: [Provider: [GroupedComponentSection]] = [:]
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var openAIGroupExpansionOverrides: [String: Bool] = [:]

    var overallIndicator: StatusIndicator {
        let indicators = summaries.values.map(\.status.indicator)
        return indicators.max() ?? .none
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshNow()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func timeline(for provider: Provider, componentId: String) -> ComponentTimeline? {
        componentTimelines[provider]?[componentId]
    }

    func sections(for provider: Provider) -> [GroupedComponentSection] {
        groupedSections[provider] ?? []
    }

    func isExpanded(_ section: GroupedComponentSection) -> Bool {
        openAIGroupExpansionOverrides[section.id] ?? (section.status != .operational)
    }

    func toggleExpansion(for section: GroupedComponentSection) {
        let currentValue = isExpanded(section)
        openAIGroupExpansionOverrides[section.id] = !currentValue
    }

    @MainActor
    func refreshNow() async {
        isLoading = true
        errorMessage = nil

        var stagedSummaries = summaries

        enum FetchResult {
            case summary(Provider, Result<StatuspageSummary, Error>)
            case officialHistory(Provider, Result<OfficialHistorySnapshot, Error>)
        }

        await withTaskGroup(of: FetchResult.self) { group in
            for provider in Provider.allCases {
                group.addTask {
                    do {
                        let summary = try await StatusClient.fetchSummary(for: provider)
                        return .summary(provider, .success(summary))
                    } catch {
                        return .summary(provider, .failure(error))
                    }
                }
            }

            group.addTask {
                do {
                    let history = try await StatusClient.fetchOpenAIOfficialHistory()
                    return .officialHistory(.openAI, .success(history))
                } catch {
                    return .officialHistory(.openAI, .failure(error))
                }
            }

            group.addTask {
                do {
                    let history = try await StatusClient.fetchAnthropicOfficialHistory()
                    return .officialHistory(.anthropic, .success(history))
                } catch {
                    return .officialHistory(.anthropic, .failure(error))
                }
            }

            var errors: [String] = []
            var officialHistories: [Provider: OfficialHistorySnapshot] = [:]
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
                summaries: stagedSummaries,
                currentTimelines: componentTimelines,
                currentSections: groupedSections,
                officialHistories: officialHistories
            )

            // Publish the refresh snapshot in one pass so the menu never renders a partial state.
            summaries = stagedSummaries
            componentTimelines = derivedState.timelines
            groupedSections = derivedState.sections
        }

        lastRefreshed = Date()
        isLoading = false
    }
}

extension StatusStore {
    static func derivePresentationState(
        summaries: [Provider: StatuspageSummary],
        currentTimelines: [Provider: [String: ComponentTimeline]],
        currentSections: [Provider: [GroupedComponentSection]],
        officialHistories: [Provider: OfficialHistorySnapshot]
    ) -> (
        timelines: [Provider: [String: ComponentTimeline]],
        sections: [Provider: [GroupedComponentSection]]
    ) {
        var nextTimelines = currentTimelines
        var nextSections = currentSections

        for provider in Provider.allCases {
            guard let summary = summaries[provider] else {
                continue
            }

            switch provider {
            case .openAI:
                if let officialHistory = officialHistories[provider], !officialHistory.groups.isEmpty {
                    let officialProjection = Self.buildOfficialOpenAISections(
                        snapshot: officialHistory,
                        currentSummary: summary
                    )
                    nextTimelines[provider] = officialProjection.timelines
                    nextSections[provider] = officialProjection.sections
                }
            case .anthropic:
                if let officialHistory = officialHistories[provider] {
                    nextTimelines[provider] = Self.buildOfficialAnthropicTimelines(
                        snapshot: officialHistory,
                        summary: summary
                    )
                } else {
                    nextTimelines[provider] = currentTimelines[provider] ?? [:]
                }
                nextSections[provider] = []
            }
        }

        return (nextTimelines, nextSections)
    }

    static func buildOfficialAnthropicTimelines(
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
                continue
            }

            timelines[component.id] = ComponentTimeline.buildUnavailable(
                title: component.name,
                now: now,
                timeZoneIdentifier: summary.page.timeZone
            )
        }

        return timelines
    }

    static func buildOfficialOpenAISections(
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

    static func currentOfficialStatus(impacts: [OfficialComponentImpact], now: Date) -> ComponentStatus {
        let activeStatuses = impacts
            .filter { $0.isActive(at: now) }
            .map(\.componentStatus)

        return activeStatuses.max() ?? .operational
    }
}
