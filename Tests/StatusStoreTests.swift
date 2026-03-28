import XCTest
@testable import MenuStatus

final class StatusStoreTests: XCTestCase {
    func testOpenAIFallbackGroupingMapsKnownComponentsIntoExpectedSections() {
        let sections = StatusStore.buildFallbackOpenAISections(
            summary: makeSummary(components: [
                makeComponent(id: "api", name: "Fine-tuning"),
                makeComponent(id: "chat", name: "GPTs"),
                makeComponent(id: "codex", name: "CLI"),
                makeComponent(id: "sora", name: "Sora"),
                makeComponent(id: "other", name: "Login"),
            ]),
            timelines: [:]
        )

        XCTAssertEqual(sections.map(\.id), ["apis", "chatGPT", "codex", "sora", "other"])
        XCTAssertEqual(sections.first(where: { $0.id == "apis" })?.components.map(\.name), ["Fine-tuning"])
        XCTAssertEqual(sections.first(where: { $0.id == "chatGPT" })?.components.map(\.name), ["GPTs"])
        XCTAssertEqual(sections.first(where: { $0.id == "codex" })?.components.map(\.name), ["CLI"])
        XCTAssertEqual(sections.first(where: { $0.id == "sora" })?.components.map(\.name), ["Sora"])
        XCTAssertEqual(sections.first(where: { $0.id == "other" })?.components.map(\.name), ["Login"])
    }

    func testUnknownComponentFallsBackToOther() {
        let sections = StatusStore.buildFallbackOpenAISections(
            summary: makeSummary(components: [
                makeComponent(id: "unknown", name: "Realtime Widgets"),
            ]),
            timelines: [:]
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.id, "other")
        XCTAssertEqual(sections.first?.components.first?.name, "Realtime Widgets")
    }

    func testGroupedStatusUsesWorstChildStatus() {
        let sections = StatusStore.buildFallbackOpenAISections(
            summary: makeSummary(components: [
                makeComponent(id: "healthy", name: "CLI", status: .operational),
                makeComponent(id: "bad", name: "Codex API", status: .majorOutage),
            ]),
            timelines: [:]
        )

        XCTAssertEqual(sections.first?.id, "codex")
        XCTAssertEqual(sections.first?.status, .majorOutage)
    }

    func testGroupedTimelineUsesWorstDayAndComputesUptime() throws {
        let sections = StatusStore.buildFallbackOpenAISections(
            summary: makeSummary(components: [
                makeComponent(id: "a", name: "CLI"),
                makeComponent(id: "b", name: "Codex API"),
            ]),
            timelines: [
                "a": makeTimeline(levels: [.operational, .degraded, .operational]),
                "b": makeTimeline(levels: [.operational, .operational, .majorOutage]),
            ]
        )

        let timeline = try XCTUnwrap(sections.first?.timeline)
        XCTAssertEqual(timeline.days.map(\.level), [.operational, .degraded, .majorOutage])
        XCTAssertEqual(timeline.uptimePercent, (1.0 / 3.0) * 100.0, accuracy: 0.001)
    }

    func testUnhealthyGroupsAutoExpandUntilUserOverridesThem() {
        let store = StatusStore()
        let unhealthySection = GroupedComponentSection(
            id: "codex",
            title: "Codex",
            components: [makeComponent(id: "codex", name: "CLI", status: .partialOutage)],
            status: .partialOutage,
            timeline: nil
        )

        XCTAssertTrue(store.isExpanded(unhealthySection))

        store.toggleExpansion(for: unhealthySection)

        XCTAssertFalse(store.isExpanded(unhealthySection))
    }

    func testParseOpenAIOfficialHistoryHTMLExtractsStructureAndMetrics() throws {
        let html = """
        <script>self.__next_f.push([1,"3:[\\"$\\",\\"$L15\\",null,{\\"slug\\":\\"status.openai.com\\",\\"initialNow\\":{\\"isoDate\\":\\"2026-03-27T17:04:55.680Z\\"},\\"summary\\":{\\"structure\\":{\\"items\\":[{\\"group\\":{\\"id\\":\\"group-apis\\",\\"name\\":\\"APIs\\",\\"hidden\\":false,\\"display_aggregated_uptime\\":true,\\"components\\":[{\\"component_id\\":\\"comp-chat\\",\\"hidden\\":false,\\"display_uptime\\":true,\\"name\\":\\"Chat Completions\\",\\"data_available_since\\":\\"2021-03-02T02:07:24.886Z\\"}]}}]}}}"])</script>
        <script>self.__next_f.push([1,"1e:[\\"$\\",\\"$L20\\",null,{\\"summary\\":\\"$5:1:props:summary\\",\\"data\\":{\\"component_impacts\\":[{\\"component_id\\":\\"comp-chat\\",\\"start_at\\":\\"2026-03-26T21:35:24.608Z\\",\\"end_at\\":\\"2026-03-26T23:17:25.337Z\\",\\"status\\":\\"degraded_performance\\",\\"status_page_incident_id\\":\\"incident-1\\"}],\\"component_uptimes\\":[{\\"component_id\\":\\"comp-chat\\",\\"status_page_component_group_id\\":null,\\"uptime\\":\\"99.99\\"},{\\"component_id\\":null,\\"status_page_component_group_id\\":\\"group-apis\\",\\"uptime\\":\\"99.98\\"}]}}]"])</script>
        """

        let payload = try StatusClient.parseOpenAIOfficialHistoryHTML(Data(html.utf8))

        XCTAssertEqual(payload.summary.structure.items.first?.group?.name, "APIs")
        XCTAssertEqual(payload.summary.structure.items.first?.group?.components.first?.name, "Chat Completions")
        XCTAssertEqual(payload.data.componentImpacts.first?.componentId, "comp-chat")
        XCTAssertEqual(payload.data.componentUptimes.first?.uptimePercent, 99.99)
        let generatedAt = try XCTUnwrap(payload.generatedAt)
        XCTAssertEqual(generatedAt.timeIntervalSince1970, 1_774_631_095.68, accuracy: 0.01)
    }
}

private func makeSummary(components: [Component]) -> StatuspageSummary {
    StatuspageSummary(
        page: StatusPage(id: "page", name: "OpenAI", url: "https://status.openai.com", updatedAt: nil),
        status: OverallStatus(indicator: .none, description: "Operational"),
        components: components,
        incidents: [],
        scheduledMaintenances: []
    )
}

private func makeComponent(
    id: String,
    name: String,
    status: ComponentStatus = .operational,
    position: Int? = nil
) -> Component {
    Component(
        id: id,
        name: name,
        status: status,
        position: position,
        description: nil,
        groupId: nil,
        group: nil,
        onlyShowIfDegraded: nil
    )
}

private func makeTimeline(levels: [TimelineDayLevel]) -> ComponentTimeline {
    let calendar = Calendar(identifier: .gregorian)
    let startDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
    let days = levels.enumerated().map { offset, level in
        DayStatus(
            date: calendar.date(byAdding: .day, value: offset, to: startDate)!,
            level: level,
            tooltip: "Day \(offset)"
        )
    }

    let healthyDays = levels.filter { $0 == .operational }.count
    let uptimePercent = Double(healthyDays) / Double(levels.count) * 100.0
    return ComponentTimeline(days: days, uptimePercent: uptimePercent)
}
