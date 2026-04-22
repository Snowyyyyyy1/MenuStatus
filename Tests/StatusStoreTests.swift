import XCTest
@testable import MenuStatus

final class StatusStoreTests: XCTestCase {
    func testMenuErrorPresentationKeepsBenchmarkErrorsOutOfFooter() {
        let messages = MenuErrorPresentation.messages(
            for: .benchmark,
            statusError: "Offline",
            benchmarkError: "Benchmark scores: HTTP 500\nGlobal index: HTTP 500"
        )

        XCTAssertEqual(messages.inline, "Benchmark scores: HTTP 500\nGlobal index: HTTP 500")
        XCTAssertNil(messages.footer)
    }

    func testMenuErrorPresentationKeepsProviderErrorsInFooter() {
        let provider = ProviderConfig.openAI
        let messages = MenuErrorPresentation.messages(
            for: .provider(provider),
            statusError: "OpenAI: HTTP 500",
            benchmarkError: "Benchmark scores: HTTP 500"
        )

        XCTAssertNil(messages.inline)
        XCTAssertEqual(messages.footer, "OpenAI: HTTP 500")
    }

    func testProviderConfigMatchesBenchmarkVendorUsingVendorIDAndDisplayName() {
        let deepSeek = ProviderConfig(
            id: "deepseek-status",
            displayName: "DeepSeek",
            baseURL: URL(string: "https://status.deepseek.com")!,
            platform: .atlassianStatuspage,
            isBuiltIn: false
        )

        XCTAssertEqual(
            ProviderConfig.provider(matchingBenchmarkVendor: "openai", in: [.anthropic, .openAI])?.id,
            ProviderConfig.openAI.id
        )
        XCTAssertEqual(
            ProviderConfig.provider(matchingBenchmarkVendor: "deepseek", in: [.anthropic, deepSeek])?.id,
            deepSeek.id
        )
        XCTAssertEqual(
            ProviderConfig.provider(matchingBenchmarkVendor: "  OPENAI\n", in: [.anthropic, .openAI])?.id,
            ProviderConfig.openAI.id
        )
        XCTAssertNil(
            ProviderConfig.provider(matchingBenchmarkVendor: "xai", in: [.anthropic, .openAI])
        )
    }

    func testTooltipOffsetUsesMeasuredMenuWidth() {
        XCTAssertEqual(
            MenuLayoutMetrics.tooltipOffsetX(dayX: 260, menuWidth: 300),
            72,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MenuLayoutMetrics.tooltipOffsetX(dayX: 20, menuWidth: 300),
            8,
            accuracy: 0.001
        )
    }

    @MainActor
    func testUnhealthyGroupsAutoExpandUntilUserOverridesThem() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let settings = SettingsStore(defaults: defaults)
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

    @MainActor
    func testGroupExpansionOverridePersistsAcrossStoreRecreation() {
        let defaults = makeIsolatedDefaults(testName: #function)
        let providerStore = ProviderConfigStore()
        let section = GroupedComponentSection(
            id: "group-apis",
            title: "APIs",
            components: [makeComponent(id: "comp-chat", name: "Chat Completions", status: .partialOutage)],
            status: .partialOutage,
            timeline: nil
        )

        let firstSettings = SettingsStore(defaults: defaults)
        firstSettings.attachProviderConfigs(providerStore)
        let firstStore = StatusStore(settings: firstSettings)

        XCTAssertTrue(firstStore.isExpanded(section, provider: ProviderConfig.openAI))

        firstStore.toggleExpansion(for: section, provider: ProviderConfig.openAI)
        XCTAssertFalse(firstStore.isExpanded(section, provider: ProviderConfig.openAI))

        let secondSettings = SettingsStore(defaults: defaults)
        secondSettings.attachProviderConfigs(providerStore)
        let secondStore = StatusStore(settings: secondSettings)

        XCTAssertFalse(secondStore.isExpanded(section, provider: ProviderConfig.openAI))
    }

    @MainActor
    func testPersistentStatusSnapshotSurvivesStoreRecreation() async {
        let defaults = makeIsolatedDefaults(testName: #function)
        let providerStore = ProviderConfigStore()
        let settings = SettingsStore(defaults: defaults)
        settings.attachProviderConfigs(providerStore)

        let provider = ProviderConfig.openAI
        let summary = StatuspageSummary(
            page: StatusPage(
                id: "page",
                name: "OpenAI",
                url: "https://status.openai.com",
                timeZone: "Etc/UTC",
                updatedAt: nil
            ),
            status: OverallStatus(indicator: .minor, description: "Minor Issues"),
            components: [
                Component(
                    id: "comp-chat",
                    name: "ChatGPT",
                    status: .operational,
                    position: 1,
                    description: nil,
                    startDate: nil,
                    groupId: "group-apis",
                    group: false,
                    onlyShowIfDegraded: nil
                ),
                Component(
                    id: "comp-api",
                    name: "API",
                    status: .partialOutage,
                    position: 2,
                    description: nil,
                    startDate: nil,
                    groupId: "group-apis",
                    group: false,
                    onlyShowIfDegraded: nil
                ),
                Component(
                    id: "group-apis",
                    name: "APIs",
                    status: .partialOutage,
                    position: 0,
                    description: nil,
                    startDate: nil,
                    groupId: nil,
                    group: true,
                    onlyShowIfDegraded: nil
                )
            ],
            incidents: [],
            scheduledMaintenances: []
        )
        let officialHistory = OfficialHistorySnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_774_631_095),
            groups: [
                OfficialHistoryGroup(
                    id: "group-apis",
                    name: "APIs",
                    hidden: false,
                    componentIDs: ["comp-chat", "comp-api"],
                    uptimePercent: 99.9
                )
            ],
            componentsByID: [
                "comp-chat": OfficialHistoryComponent(
                    id: "comp-chat",
                    name: "ChatGPT",
                    hidden: false,
                    displayUptime: true,
                    dataAvailableSince: nil,
                    uptimePercent: 99.99,
                    timelineSource: .impacts([])
                ),
                "comp-api": OfficialHistoryComponent(
                    id: "comp-api",
                    name: "API",
                    hidden: false,
                    displayUptime: true,
                    dataAvailableSince: nil,
                    uptimePercent: 99.5,
                    timelineSource: .impacts([
                        OfficialComponentImpact(
                            componentId: "comp-api",
                            endAt: "2026-04-14T11:30:00Z",
                            startAt: "2026-04-14T10:00:00Z",
                            status: .partialOutage,
                            statusPageIncidentId: "incident-1"
                        )
                    ])
                )
            ],
            incidentNames: ["incident-1": "API partial outage"]
        )

        let fetcher = StatusStore.Fetcher(
            fetchSummary: { _ in summary },
            fetchOfficialHistory: { _ in officialHistory },
            fetchIncidents: { _ in [] },
            fetchScheduledMaintenances: { _ in [] },
            fetchHistoryPageIncidents: { _ in [] }
        )

        let firstStore = StatusStore(settings: settings, defaults: defaults)
        await firstStore.refreshNow(fetcher: fetcher)

        let secondSettings = SettingsStore(defaults: defaults)
        secondSettings.attachProviderConfigs(providerStore)
        let secondStore = StatusStore(settings: secondSettings, defaults: defaults)

        XCTAssertEqual(secondStore.summaries[provider]?.status.description, "Minor Issues")
        XCTAssertEqual(secondStore.sections(for: provider).map { $0.title }, ["APIs"])
        XCTAssertEqual(secondStore.timeline(for: provider, componentId: "comp-api")?.uptimePercent, 99.5)
        XCTAssertEqual(
            secondStore.dayDetails(for: provider, componentId: "comp-api").values.flatMap { $0 }.first?.incidentName,
            "API partial outage"
        )
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

    func testParseOpenAIOfficialHistoryHTMLKeepsLastDuplicateComponentID() throws {
        let html = """
        <script>self.__next_f.push([1,"3:[\\"$\\",\\"$L15\\",null,{\\"slug\\":\\"status.openai.com\\",\\"initialNow\\":{\\"isoDate\\":\\"2026-03-27T17:04:55.680Z\\"},\\"summary\\":{\\"structure\\":{\\"items\\":[{\\"group\\":{\\"id\\":\\"group-apis\\",\\"name\\":\\"APIs\\",\\"hidden\\":false,\\"display_aggregated_uptime\\":true,\\"components\\":[{\\"component_id\\":\\"comp-chat\\",\\"hidden\\":false,\\"display_uptime\\":true,\\"name\\":\\"Old Chat\\",\\"data_available_since\\":\\"2021-03-02T02:07:24.886Z\\"},{\\"component_id\\":\\"comp-chat\\",\\"hidden\\":false,\\"display_uptime\\":true,\\"name\\":\\"New Chat\\",\\"data_available_since\\":\\"2021-03-02T02:07:24.886Z\\"}]}}]}}}"])</script>
        <script>self.__next_f.push([1,"1e:[\\"$\\",\\"$L20\\",null,{\\"summary\\":\\"$5:1:props:summary\\",\\"data\\":{\\"component_impacts\\":[{\\"component_id\\":\\"comp-chat\\",\\"start_at\\":\\"2026-03-26T21:35:24.608Z\\",\\"end_at\\":\\"2026-03-26T23:17:25.337Z\\",\\"status\\":\\"degraded_performance\\",\\"status_page_incident_id\\":\\"incident-1\\"}],\\"component_uptimes\\":[{\\"component_id\\":\\"comp-chat\\",\\"status_page_component_group_id\\":null,\\"uptime\\":\\"99.90\\"},{\\"component_id\\":\\"comp-chat\\",\\"status_page_component_group_id\\":null,\\"uptime\\":\\"99.99\\"},{\\"component_id\\":null,\\"status_page_component_group_id\\":\\"group-apis\\",\\"uptime\\":\\"99.98\\"}]}}]"])</script>
        """

        let payload = try StatusClient.parseIncidentIOHistoryHTML(Data(html.utf8))

        XCTAssertEqual(payload.componentsByID["comp-chat"]?.name, "New Chat")
        XCTAssertEqual(payload.componentsByID["comp-chat"]?.uptimePercent, 99.99)
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
                    <rect class="uptime-day component-claude day-1" fill="#e04343" />
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

    private func makeIsolatedDefaults(testName: String) -> UserDefaults {
        let suiteName = "StatusStoreTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
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
