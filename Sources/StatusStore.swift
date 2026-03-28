import Foundation
import Observation

@Observable
final class StatusStore {
    var summaries: [Provider: StatuspageSummary] = [:]
    var incidents: [Provider: [Incident]] = [:]
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

        enum FetchResult {
            case summary(Provider, Result<StatuspageSummary, Error>)
            case incidents(Provider, Result<[Incident], Error>)
            case openAIHistory(Result<OpenAIOfficialHistoryPayload, Error>)
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
                group.addTask {
                    do {
                        let incidents = try await StatusClient.fetchIncidents(for: provider)
                        return .incidents(provider, .success(incidents))
                    } catch {
                        return .incidents(provider, .failure(error))
                    }
                }
            }

            group.addTask {
                do {
                    let history = try await StatusClient.fetchOpenAIOfficialHistory()
                    return .openAIHistory(.success(history))
                } catch {
                    return .openAIHistory(.failure(error))
                }
            }

            var errors: [String] = []
            var openAIHistory: OpenAIOfficialHistoryPayload?
            for await result in group {
                switch result {
                case .summary(let provider, .success(let summary)):
                    summaries[provider] = summary
                case .summary(let provider, .failure(let error)):
                    errors.append("\(provider.displayName): \(error.localizedDescription)")
                case .incidents(let provider, .success(let incidents)):
                    self.incidents[provider] = incidents
                case .incidents(_, .failure):
                    break
                case .openAIHistory(.success(let history)):
                    openAIHistory = history
                case .openAIHistory(.failure):
                    break
                }
            }

            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
            }
            applyDerivedState(using: openAIHistory)
        }

        lastRefreshed = Date()
        isLoading = false
    }
}

extension StatusStore {
    private func applyDerivedState(using openAIHistory: OpenAIOfficialHistoryPayload?) {
        for provider in Provider.allCases {
            guard let summary = summaries[provider],
                  let providerIncidents = incidents[provider] else {
                continue
            }

            switch provider {
            case .openAI:
                if let openAIHistory {
                    let officialProjection = Self.buildOfficialOpenAISections(
                        payload: openAIHistory,
                        currentSummary: summary
                    )
                    componentTimelines[provider] = officialProjection.timelines
                    groupedSections[provider] = officialProjection.sections
                } else {
                    let fallbackTimelines = Self.buildIncidentTimelines(
                        summary: summary,
                        incidents: providerIncidents
                    )
                    componentTimelines[provider] = fallbackTimelines
                    groupedSections[provider] = Self.buildFallbackOpenAISections(
                        summary: summary,
                        timelines: fallbackTimelines
                    )
                }
            case .anthropic:
                componentTimelines[provider] = Self.buildIncidentTimelines(
                    summary: summary,
                    incidents: providerIncidents
                )
                groupedSections[provider] = []
            }
        }
    }

    static func buildIncidentTimelines(
        summary: StatuspageSummary,
        incidents: [Incident]
    ) -> [String: ComponentTimeline] {
        var timelines: [String: ComponentTimeline] = [:]
        let visibleComponents = summary.components.filter { $0.group != true }

        for component in visibleComponents {
            timelines[component.id] = ComponentTimeline.build(
                incidents: incidents,
                componentId: component.id
            )
        }

        return timelines
    }

    static func buildOfficialOpenAISections(
        payload: OpenAIOfficialHistoryPayload,
        currentSummary: StatuspageSummary
    ) -> (sections: [GroupedComponentSection], timelines: [String: ComponentTimeline]) {
        let now = payload.generatedAt ?? Date()
        let summaryStatuses = Dictionary(uniqueKeysWithValues: currentSummary.components.map { ($0.id, $0.status) })
        let groupedImpacts = payload.data.impactsByComponentID
        let componentUptimes = payload.data.uptimeByComponentID
        let groupUptimes = payload.data.uptimeByGroupID

        var timelines: [String: ComponentTimeline] = [:]
        let sections = payload.summary.structure.items.compactMap { item -> GroupedComponentSection? in
            guard let group = item.group, !group.hidden else { return nil }

            let components = group.components
                .filter { $0.hidden == false && ($0.displayUptime ?? true) }
                .map { member -> Component in
                    let currentImpactStatus = currentOfficialStatus(
                        impacts: groupedImpacts[member.componentId] ?? [],
                        now: now
                    )
                    let currentStatus = max(
                        summaryStatuses[member.componentId] ?? .operational,
                        currentImpactStatus
                    )

                    let timeline = ComponentTimeline.buildFromImpacts(
                        impacts: groupedImpacts[member.componentId] ?? [],
                        now: now,
                        uptimePercentOverride: componentUptimes[member.componentId],
                        title: member.name
                    )
                    timelines[member.componentId] = timeline

                    return Component(
                        id: member.componentId,
                        name: member.name,
                        status: currentStatus,
                        position: nil,
                        description: nil,
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
                    uptimePercentOverride: groupUptimes[group.id]
                )
            )
        }

        return (sections, timelines)
    }

    static func buildFallbackOpenAISections(
        summary: StatuspageSummary,
        timelines: [String: ComponentTimeline]
    ) -> [GroupedComponentSection] {
        let components = summary.components
            .filter { $0.group != true }
            .sorted { lhs, rhs in
                (lhs.position ?? .max, lhs.name) < (rhs.position ?? .max, rhs.name)
            }

        let grouped = Dictionary(grouping: components, by: openAIGroup(for:))

        return OpenAIGroupID.allCases.compactMap { groupID in
            guard let groupComponents = grouped[groupID], !groupComponents.isEmpty else {
                return nil
            }

            let status = groupComponents.map(\.status).max() ?? .operational
            let groupTimelines = groupComponents.compactMap { timelines[$0.id] }

            return GroupedComponentSection(
                id: groupID.rawValue,
                title: groupID.title,
                components: groupComponents,
                status: status,
                timeline: ComponentTimeline.aggregate(groupTimelines, title: groupID.title)
            )
        }
    }

    static func currentOfficialStatus(impacts: [OfficialComponentImpact], now: Date) -> ComponentStatus {
        let activeStatuses = impacts
            .filter { $0.isActive(at: now) }
            .map(\.componentStatus)

        return activeStatuses.max() ?? .operational
    }

    static func openAIGroup(for component: Component) -> OpenAIGroupID {
        let explicitMapping: [String: OpenAIGroupID] = [
            "Fine-tuning": .apis,
            "Embeddings": .apis,
            "Images": .apis,
            "Batch": .apis,
            "Audio": .apis,
            "Moderations": .apis,
            "Compliance API": .apis,
            "Conversations": .chatGPT,
            "Voice mode": .chatGPT,
            "GPTs": .chatGPT,
            "Image Generation": .chatGPT,
            "Deep Research": .chatGPT,
            "Agent": .chatGPT,
            "Connectors/Apps": .chatGPT,
            "App": .chatGPT,
            "Codex Web": .codex,
            "Codex API": .codex,
            "CLI": .codex,
            "VS Code extension": .codex,
            "Sora": .sora,
            "Video viewing": .sora,
            "Login": .other,
            "ChatGPT Atlas": .other,
        ]

        if let group = explicitMapping[component.name] {
            return group
        }

        if component.name.localizedCaseInsensitiveContains("fedramp") {
            return .fedRAMP
        }

        return .other
    }
}
