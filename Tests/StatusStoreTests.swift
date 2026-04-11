import XCTest
@testable import MenuStatus

final class StatusStoreTests: XCTestCase {
    @MainActor
    func testUnhealthyGroupsAutoExpandUntilUserOverridesThem() {
        let settings = SettingsStore()
        settings.attachProviderConfigs(ProviderConfigStore())
        let store = StatusStore(settings: settings)
        let provider = ProviderConfig.openAI
        let unhealthySection = GroupedComponentSection(
            id: "codex",
            title: "Codex",
            components: [makeComponent(id: "codex", name: "CLI", status: .partialOutage)],
            status: .partialOutage,
            timeline: nil
        )

        XCTAssertTrue(store.isExpanded(unhealthySection, provider: provider))

        store.toggleExpansion(for: unhealthySection, provider: provider)

        XCTAssertFalse(store.isExpanded(unhealthySection, provider: provider))
    }

    func testParseOpenAIOfficialHistoryHTMLExtractsStructureAndMetrics() throws {
        let html = """
        <script>self.__next_f.push([1,"3:[\\"$\\",\\"$L15\\",null,{\\"slug\\":\\"status.openai.com\\",\\"initialNow\\":{\\"isoDate\\":\\"2026-03-27T17:04:55.680Z\\"},\\"summary\\":{\\"structure\\":{\\"items\\":[{\\"group\\":{\\"id\\":\\"group-apis\\",\\"name\\":\\"APIs\\",\\"hidden\\":false,\\"display_aggregated_uptime\\":true,\\"components\\":[{\\"component_id\\":\\"comp-chat\\",\\"hidden\\":false,\\"display_uptime\\":true,\\"name\\":\\"Chat Completions\\",\\"data_available_since\\":\\"2021-03-02T02:07:24.886Z\\"}]}}]}}}"])</script>
        <script>self.__next_f.push([1,"1e:[\\"$\\",\\"$L20\\",null,{\\"summary\\":\\"$5:1:props:summary\\",\\"data\\":{\\"component_impacts\\":[{\\"component_id\\":\\"comp-chat\\",\\"start_at\\":\\"2026-03-26T21:35:24.608Z\\",\\"end_at\\":\\"2026-03-26T23:17:25.337Z\\",\\"status\\":\\"degraded_performance\\",\\"status_page_incident_id\\":\\"incident-1\\"}],\\"component_uptimes\\":[{\\"component_id\\":\\"comp-chat\\",\\"status_page_component_group_id\\":null,\\"uptime\\":\\"99.99\\"},{\\"component_id\\":null,\\"status_page_component_group_id\\":\\"group-apis\\",\\"uptime\\":\\"99.98\\"}]}}]"])</script>
        """

        let payload = try StatusClient.parseIncidentIOHistoryHTML(Data(html.utf8))

        XCTAssertEqual(payload.groups.first?.name, "APIs")
        XCTAssertEqual(payload.componentsByID["comp-chat"]?.name, "Chat Completions")
        XCTAssertEqual(payload.componentsByID["comp-chat"]?.impacts.first?.componentId, "comp-chat")
        XCTAssertEqual(payload.componentsByID["comp-chat"]?.uptimePercent, 99.99)
        let generatedAt = try XCTUnwrap(payload.generatedAt)
        XCTAssertEqual(generatedAt.timeIntervalSince1970, 1_774_631_095.68, accuracy: 0.01)
    }

    func testDerivePresentationStatePreservesExistingDerivedDataUntilInputsAreComplete() {
        let existingTimeline = makeTimeline(levels: [.operational, .operational])
        let existingSection = GroupedComponentSection(
            id: "existing",
            title: "Existing",
            components: [makeComponent(id: "existing", name: "Existing")],
            status: .operational,
            timeline: existingTimeline
        )

        let provider = ProviderConfig.openAI
        let derivedState = StatusStore.derivePresentationState(
            providers: [provider],
            summaries: [
                provider: makeSummary(components: [
                    makeComponent(id: "api", name: "Fine-tuning"),
                ]),
            ],
            currentTimelines: [provider: ["existing": existingTimeline]],
            currentSections: [provider: [existingSection]],
            officialHistories: [:]
        )

        XCTAssertEqual(derivedState.timelines[provider]?["existing"]?.days.count, existingTimeline.days.count)
        XCTAssertEqual(derivedState.sections[provider]?.map(\.id), ["existing"])
    }

    func testParseAnthropicOfficialHistoryHTMLExtractsComponentUptime() throws {
        let html = """
        <html>
          <head>
            <meta name="issued" content="1774685401">
          </head>
          <body>
            <main>
              <div data-component-id="claude">
                <span class="name">claude.ai</span>
                <div class="shared-partial uptime-90-days-wrapper">
                  <svg class="availability-time-line-graphic">
                    <rect fill="#76ad2a" class="uptime-day component-claude day-0" />
                    <rect fill="#e04343" class="uptime-day component-claude day-1" />
                  </svg>
                  <span id="uptime-percent-claude"><var data-var="uptime-percent">98.95</var></span>
                </div>
              </div>
              <div data-component-id="code">
                <span class="name">Claude Code</span>
                <div class="shared-partial uptime-90-days-wrapper">
                  <svg class="availability-time-line-graphic">
                    <rect fill="#76ad2a" class="uptime-day component-code day-0" />
                    <rect fill="#76ad2a" class="uptime-day component-code day-1" />
                  </svg>
                  <span id="uptime-percent-code"><var data-var="uptime-percent">99.27</var></span>
                </div>
              </div>
            </main>
          </body>
        </html>
        """

        let payload = try StatusClient.parseAtlassianStatuspageHistoryHTML(Data(html.utf8))

        XCTAssertEqual(payload.componentsByID["claude"]?.name, "claude.ai")
        XCTAssertEqual(payload.componentsByID["claude"]?.uptimePercent, 98.95)
        XCTAssertEqual(payload.componentsByID["claude"]?.fills, ["#76ad2a", "#e04343"])
        XCTAssertEqual(payload.componentsByID["code"]?.uptimePercent, 99.27)
        XCTAssertEqual(payload.generatedAt?.timeIntervalSince1970 ?? 0, 1_774_685_401, accuracy: 0.01)
    }

    func testBuildOfficialAnthropicTimelinesUsesOfficialPercentages() {
        let summary = makeSummary(components: [
            makeComponent(id: "claude", name: "claude.ai"),
            makeComponent(id: "platform", name: "platform.claude.com (formerly console.anthropic.com)"),
            makeComponent(id: "code", name: "Claude Code"),
        ])
        let officialHistory = OfficialHistorySnapshot(
            generatedAt: nil,
            groups: [],
            componentsByID: [
                "claude": OfficialHistoryComponent(id: "claude", name: "claude.ai", hidden: false, displayUptime: true, dataAvailableSince: nil, uptimePercent: 98.95, timelineSource: .colors(["#76ad2a"])),
                "platform": OfficialHistoryComponent(id: "platform", name: "platform.claude.com (formerly console.anthropic.com)", hidden: false, displayUptime: true, dataAvailableSince: nil, uptimePercent: 99.31, timelineSource: .colors(["#76ad2a"])),
                "code": OfficialHistoryComponent(id: "code", name: "Claude Code", hidden: false, displayUptime: true, dataAvailableSince: nil, uptimePercent: 99.27, timelineSource: .colors(["#76ad2a"])),
            ],
            incidentNames: [:]
        )

        let timelines = StatusStore.buildFlatTimelines(
            snapshot: officialHistory,
            summary: summary
        )

        XCTAssertEqual(timelines["claude"]?.uptimePercent ?? 0, 98.95, accuracy: 0.001)
        XCTAssertEqual(timelines["platform"]?.uptimePercent ?? 0, 99.31, accuracy: 0.001)
        XCTAssertEqual(timelines["code"]?.uptimePercent ?? 0, 99.27, accuracy: 0.001)
    }

    func testBuildOfficialAnthropicTimelinesUsesOfficialBarColors() {
        let summary = StatuspageSummary(
            page: StatusPage(id: "page", name: "Claude", url: "https://status.claude.com", timeZone: "Etc/UTC", updatedAt: nil),
            status: OverallStatus(indicator: .none, description: "Operational"),
            components: [makeComponent(id: "claude", name: "claude.ai")],
            incidents: [],
            scheduledMaintenances: []
        )
        let payload = OfficialHistorySnapshot(
            generatedAt: Date(timeIntervalSince1970: 1774685401),
            groups: [],
            componentsByID: [
                "claude": OfficialHistoryComponent(
                    id: "claude",
                    name: "claude.ai",
                    hidden: false,
                    displayUptime: true,
                    dataAvailableSince: nil,
                    uptimePercent: 98.95,
                    timelineSource: .colors(["#76ad2a", "#e04343", "#B0AEA5"])
                )
            ],
            incidentNames: [:]
        )

        let timeline = StatusStore.buildFlatTimelines(
            snapshot: payload,
            summary: summary
        )["claude"]

        XCTAssertEqual(timeline?.uptimePercent, 98.95)
        XCTAssertEqual(
            timeline?.days.map(\.level) ?? [],
            [TimelineDayLevel.operational, .majorOutage, .noData]
        )
    }

    func testBuildOfficialAnthropicTimelinesMarksMissingComponentAsUnavailable() {
        let summary = StatuspageSummary(
            page: StatusPage(id: "page", name: "Claude", url: "https://status.claude.com", timeZone: "Etc/UTC", updatedAt: nil),
            status: OverallStatus(indicator: .none, description: "Operational"),
            components: [makeComponent(id: "missing", name: "Missing")],
            incidents: [],
            scheduledMaintenances: []
        )
        let payload = OfficialHistorySnapshot(generatedAt: nil, groups: [], componentsByID: [:], incidentNames: [:])

        let timeline = StatusStore.buildFlatTimelines(
            snapshot: payload,
            summary: summary
        )["missing"]

        XCTAssertEqual(timeline?.days.allSatisfy { $0.level == TimelineDayLevel.noData }, true)
        XCTAssertEqual(timeline?.hasMeasuredDays, false)
    }

    func testBuildFromImpactsUsesProvidedTimeZoneAndAvailabilityDate() throws {
        let now = try XCTUnwrap(DateParsing.parseISODate("2026-03-23T12:00:00Z"))
        let impacts = [
            OfficialComponentImpact(
                componentId: "claude",
                endAt: "2026-03-23T00:10:00Z",
                startAt: "2026-03-22T23:50:00Z",
                status: .fullOutage,
                statusPageIncidentId: nil
            )
        ]

        let utcTimeline = ComponentTimeline.buildFromImpacts(
            impacts: impacts,
            now: now,
            numDays: 2,
            title: "claude.ai",
            timeZoneIdentifier: "Etc/UTC"
        )
        let availableTimeline = ComponentTimeline.buildFromImpacts(
            impacts: [],
            now: now,
            numDays: 3,
            title: "claude.ai",
            timeZoneIdentifier: "Etc/UTC",
            availableSince: "2026-03-22"
        )

        XCTAssertEqual(utcTimeline.days.map(\.level), [TimelineDayLevel.majorOutage, .majorOutage])
        XCTAssertEqual(availableTimeline.days.map(\.level), [.noData, .operational, .operational])
    }
}

private func makeSummary(components: [Component]) -> StatuspageSummary {
    StatuspageSummary(
        page: StatusPage(id: "page", name: "OpenAI", url: "https://status.openai.com", timeZone: nil, updatedAt: nil),
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
    position: Int? = nil,
    startDate: String? = nil
) -> Component {
    Component(
        id: id,
        name: name,
        status: status,
        position: position,
        description: nil,
        startDate: startDate,
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
