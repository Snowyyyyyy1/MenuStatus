import Foundation
import SwiftUI

// MARK: - Platform & Provider

enum StatusPlatform: String, Codable {
    case atlassianStatuspage
    case incidentIO
}

struct ProviderConfig: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var baseURL: URL
    var platform: StatusPlatform
    var isBuiltIn: Bool

    var apiURL: URL { baseURL.appendingPathComponent("api/v2/summary.json") }
    var statusPageURL: URL { baseURL }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension ProviderConfig {
    static let openAI = ProviderConfig(
        id: "openai", displayName: "OpenAI",
        baseURL: URL(string: "https://status.openai.com")!,
        platform: .incidentIO, isBuiltIn: true
    )
    static let anthropic = ProviderConfig(
        id: "anthropic", displayName: "Claude",
        baseURL: URL(string: "https://status.claude.com")!,
        platform: .atlassianStatuspage, isBuiltIn: true
    )
    static let builtInProviders: [ProviderConfig] = [.openAI, .anthropic]
}

// MARK: - Statuspage API Response

struct StatuspageSummary: Codable {
    let page: StatusPage
    let status: OverallStatus
    let components: [Component]
    let incidents: [Incident]?
    let scheduledMaintenances: [Incident]?
}

struct StatusPage: Codable {
    let id: String
    let name: String
    let url: String
    let timeZone: String?
    let updatedAt: String?
}

struct OverallStatus: Codable {
    let indicator: StatusIndicator
    let description: String
}

// MARK: - Status Indicator

enum StatusIndicator: String, Codable, Comparable {
    case none
    case minor
    case major
    case critical
    case maintenance

    var displayName: String {
        switch self {
        case .none: "Operational"
        case .minor: "Minor Issues"
        case .major: "Major Outage"
        case .critical: "Critical Outage"
        case .maintenance: "Maintenance"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none: "checkmark.circle.fill"
        case .minor: "minus.square.fill"
        case .major: "exclamationmark.triangle.fill"
        case .critical: "xmark.circle.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .none: "checkmark.circle"
        case .minor: "minus.square"
        case .major: "exclamationmark.triangle"
        case .critical: "xmark.circle"
        case .maintenance: "wrench.and.screwdriver"
        }
    }

    var color: Color {
        switch self {
        case .none: .green
        case .minor: .yellow
        case .major: .orange
        case .critical: .red
        case .maintenance: .blue
        }
    }

    /// Impact label for use in incident/maintenance badges (distinct from page-level displayName)
    var impactLabel: String {
        switch self {
        case .none: "None"
        case .minor: "Minor"
        case .major: "Major"
        case .critical: "Critical"
        case .maintenance: "Maintenance"
        }
    }

    /// Color for incident/maintenance impact badges
    var impactColor: Color {
        switch self {
        case .none: .secondary
        case .minor: .yellow
        case .major: .orange
        case .critical: .red
        case .maintenance: .blue
        }
    }

    private var severity: Int {
        switch self {
        case .none: 0
        case .maintenance: 1
        case .minor: 2
        case .major: 3
        case .critical: 4
        }
    }

    static func < (lhs: StatusIndicator, rhs: StatusIndicator) -> Bool {
        lhs.severity < rhs.severity
    }
}

// MARK: - Component

struct Component: Codable, Identifiable {
    let id: String
    let name: String
    let status: ComponentStatus
    let position: Int?
    let description: String?
    let startDate: String?
    let groupId: String?
    let group: Bool?
    let onlyShowIfDegraded: Bool?
}

enum ComponentStatus: String, Codable {
    case operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case underMaintenance = "under_maintenance"

    var displayName: String {
        switch self {
        case .operational: "Operational"
        case .degradedPerformance: "Degraded"
        case .partialOutage: "Partial Outage"
        case .majorOutage: "Major Outage"
        case .underMaintenance: "Maintenance"
        }
    }

    var color: Color {
        switch self {
        case .operational: .green
        case .degradedPerformance: .yellow
        case .partialOutage: .orange
        case .majorOutage: .red
        case .underMaintenance: .blue
        }
    }

    fileprivate var severity: Int {
        switch self {
        case .operational: 0
        case .degradedPerformance: 1
        case .underMaintenance: 2
        case .partialOutage: 3
        case .majorOutage: 4
        }
    }
}

extension ComponentStatus: Comparable {
    static func < (lhs: ComponentStatus, rhs: ComponentStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}

// MARK: - Incident

enum IncidentStatus: String, Codable {
    case investigating
    case identified
    case monitoring
    case resolved
    case postmortem
    // Maintenance-specific statuses (Statuspage reuses Incident shape for scheduled_maintenances)
    case scheduled
    case inProgress = "in_progress"
    case verifying
    case completed

    var isActive: Bool {
        switch self {
        case .investigating, .identified, .monitoring, .scheduled, .inProgress, .verifying: true
        case .resolved, .postmortem, .completed: false
        }
    }
}

struct Incident: Codable, Identifiable {
    let id: String
    let name: String
    let status: IncidentStatus
    let impact: StatusIndicator?
    let shortlink: String?
    let startedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let monitoringAt: String?
    let resolvedAt: String?
    let incidentUpdates: [IncidentUpdate]?
    let components: [IncidentComponent]?
}

struct IncidentComponent: Codable {
    let id: String
    let name: String?
    let status: ComponentStatus?
}

struct IncidentUpdate: Codable, Identifiable {
    let id: String
    let status: String
    let body: String
    let createdAt: String?
    let affectedComponents: [AffectedComponent]?
}

struct AffectedComponent: Codable {
    let code: String
    let name: String
    let oldStatus: String
    let newStatus: String
}

// MARK: - Incident History Response

struct IncidentHistoryResponse: Codable {
    let incidents: [Incident]
}

struct ScheduledMaintenancesResponse: Codable {
    let scheduledMaintenances: [Incident]
}

struct HistoryPageIncident {
    let code: String
    let name: String
    let impact: StatusIndicator?
    let startedAt: Date
    let resolvedAt: Date
}

// MARK: - Day Incident Detail

struct DayIncidentDetail {
    let level: TimelineDayLevel
    let durationSeconds: TimeInterval
    let incidentName: String?
}

// MARK: - Tooltip State

@Observable
final class TooltipState {
    var info: TooltipInfo?

    struct TooltipInfo {
        let day: DayStatus
        let details: [DayIncidentDetail]
        let dayX: CGFloat
        let barMinY: CGFloat
        let barMaxY: CGFloat
    }
}

// MARK: - Daily Uptime

struct DayStatus: Identifiable {
    let id: Date
    let date: Date
    let level: TimelineDayLevel
    let color: Color
    let tooltip: String

    init(date: Date, level: TimelineDayLevel, tooltip: String) {
        self.id = date
        self.date = date
        self.level = level
        self.color = level.color
        self.tooltip = tooltip
    }
}

enum TimelineDayLevel: Int, Comparable {
    case noData
    case operational
    case degraded
    case maintenance
    case partialOutage
    case majorOutage

    var color: Color {
        switch self {
        case .noData: .gray.opacity(0.45)
        case .operational: .green
        case .degraded: .yellow
        case .maintenance: .blue
        case .partialOutage: .orange
        case .majorOutage: .red
        }
    }

    var displayName: String {
        switch self {
        case .noData: "no data"
        case .operational: "operational"
        case .degraded: "degraded"
        case .maintenance: "maintenance"
        case .partialOutage: "partial outage"
        case .majorOutage: "major outage"
        }
    }

    static func < (lhs: TimelineDayLevel, rhs: TimelineDayLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Component Timeline

struct ComponentTimeline {
    let days: [DayStatus]
    let uptimePercent: Double
    var isEstimated: Bool = false

    var hasMeasuredDays: Bool {
        days.contains { $0.level != .noData }
    }

    static func buildFromColors(
        fills: [String],
        now: Date,
        timeZoneIdentifier: String?,
        title: String,
        uptimePercent: Double
    ) -> ComponentTimeline {
        let calendar = configuredCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "M/d"

        let days = fills.enumerated().compactMap { index, fill -> DayStatus? in
            guard let date = calendar.date(byAdding: .day, value: -(fills.count - 1 - index), to: today) else {
                return nil
            }
            let label = formatter.string(from: date)
            let level = timelineLevel(forFillHex: fill)
            return DayStatus(
                date: date,
                level: level,
                tooltip: "\(label): \(title) \(level.displayName)"
            )
        }

        return ComponentTimeline(days: days, uptimePercent: uptimePercent)
    }

    static func buildUnavailable(
        title: String,
        now: Date,
        timeZoneIdentifier: String?
    ) -> ComponentTimeline {
        let calendar = configuredCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "M/d"

        let days: [DayStatus] = (0..<90).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let label = formatter.string(from: date)
            return DayStatus(date: date, level: .noData, tooltip: "\(label): \(title) no data")
        }

        return ComponentTimeline(days: days, uptimePercent: 0)
    }

    static func build(
        from officialComponent: OfficialHistoryComponent,
        now: Date,
        timeZoneIdentifier: String?
    ) -> ComponentTimeline {
        switch officialComponent.timelineSource {
        case .impacts(let impacts):
            buildFromImpacts(
                impacts: impacts,
                now: now,
                uptimePercentOverride: officialComponent.uptimePercent,
                title: officialComponent.name,
                timeZoneIdentifier: timeZoneIdentifier,
                availableSince: officialComponent.dataAvailableSince
            )
        case .colors(let fills):
            buildFromColors(
                fills: fills,
                now: now,
                timeZoneIdentifier: timeZoneIdentifier,
                title: officialComponent.name,
                uptimePercent: officialComponent.uptimePercent ?? 0
            )
        }
    }

    static func buildFromImpacts(
        impacts: [OfficialComponentImpact],
        now: Date,
        numDays: Int = 90,
        uptimePercentOverride: Double? = nil,
        title: String,
        timeZoneIdentifier: String? = nil,
        availableSince: String? = nil
    ) -> ComponentTimeline {
        let calendar = configuredCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let availableDate = startOfDay(from: availableSince, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "M/d"

        var dayImpacts: [Date: TimelineDayLevel] = [:]
        for impact in impacts {
            guard let startAt = parseISODate(impact.startAt) else { continue }
            let impactEnd = parseISODate(impact.endAt) ?? now
            let start = calendar.startOfDay(for: startAt)
            let end = calendar.startOfDay(for: impactEnd)

            var day = start
            while day <= end && day <= today {
                let newLevel = impact.timelineLevel
                if newLevel > (dayImpacts[day] ?? .operational) {
                    dayImpacts[day] = newLevel
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        let days: [DayStatus] = (0..<numDays).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let label = formatter.string(from: date)

            if let availableDate, date < availableDate {
                return DayStatus(date: date, level: .noData, tooltip: "\(label): no data")
            }

            let level = dayImpacts[date] ?? .operational
            return DayStatus(
                date: date,
                level: level,
                tooltip: "\(label): \(title) \(level.displayName)"
            )
        }

        let healthyDays = days.filter { $0.level == .operational }.count
        let uptime = uptimePercentOverride ?? (Double(healthyDays) / Double(days.count) * 100.0)
        return ComponentTimeline(days: days, uptimePercent: uptime)
    }

    static func buildEstimated(
        from dayDetails: [Date: [DayIncidentDetail]],
        title: String,
        now: Date,
        numDays: Int = 90,
        timeZoneIdentifier: String? = nil
    ) -> ComponentTimeline {
        let calendar = configuredCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "M/d"

        let days: [DayStatus] = (0..<numDays).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let label = formatter.string(from: date)
            let details = dayDetails[date] ?? []
            let level = details.map(\.level).max() ?? .operational
            return DayStatus(
                date: date,
                level: level,
                tooltip: "\(label): \(title) \(level.displayName)"
            )
        }

        let healthyDays = days.filter { $0.level == .operational }.count
        let uptime = Double(healthyDays) / Double(days.count) * 100.0
        return ComponentTimeline(days: days, uptimePercent: uptime, isEstimated: true)
    }

    static func aggregate(
        _ timelines: [ComponentTimeline],
        title: String,
        uptimePercentOverride: Double? = nil
    ) -> ComponentTimeline? {
        guard let first = timelines.first else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"

        let aggregatedDays = first.days.enumerated().map { index, referenceDay in
            let worstLevel: TimelineDayLevel = timelines
                .compactMap { timeline -> TimelineDayLevel? in
                    guard timeline.days.indices.contains(index) else { return nil }
                    return timeline.days[index].level
                }
                .max() ?? TimelineDayLevel.operational

            let label = formatter.string(from: referenceDay.date)
            return DayStatus(
                date: referenceDay.date,
                level: worstLevel,
                tooltip: "\(label): \(title) \(worstLevel.displayName)"
            )
        }

        let healthyDays = aggregatedDays.filter { $0.level == TimelineDayLevel.operational }.count
        let uptime = uptimePercentOverride ?? (Double(healthyDays) / Double(aggregatedDays.count) * 100.0)
        return ComponentTimeline(days: aggregatedDays, uptimePercent: uptime)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISODate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoFallback.date(from: s)
    }

    private static func configuredCalendar(timeZoneIdentifier: String?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    private static func startOfDay(from startDate: String?, calendar: Calendar) -> Date? {
        guard let startDate else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: startDate) else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func timelineLevel(forFillHex fill: String) -> TimelineDayLevel {
        switch normalizedHex(fill) {
        case "b0aea5":
            return .noData
        case "76ad2a":
            return .operational
        case "2c84db":
            return .maintenance
        default:
            let (r, g, _) = rgbComponents(for: fill)
            if r > 210 && g < 120 {
                return .majorOutage
            }
            if r > 225 && g < 170 {
                return .partialOutage
            }
            if r > 180 && g >= 120 {
                return .degraded
            }
            return .operational
        }
    }

    private static func normalizedHex(_ fill: String) -> String {
        fill.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
    }

    private static func rgbComponents(for fill: String) -> (Int, Int, Int) {
        let hex = normalizedHex(fill)
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return (0, 0, 0)
        }
        return ((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff)
    }

}

struct GroupedComponentSection: Identifiable {
    let id: String
    let title: String
    let components: [Component]
    let status: ComponentStatus
    let timeline: ComponentTimeline?

    var componentCount: Int {
        components.count
    }
}

struct OfficialHistorySnapshot {
    let generatedAt: Date?
    let groups: [OfficialHistoryGroup]
    let componentsByID: [String: OfficialHistoryComponent]
    let incidentNames: [String: String]  // incidentId → name
}

struct OfficialHistoryGroup {
    let id: String
    let name: String
    let hidden: Bool
    let componentIDs: [String]
    let uptimePercent: Double?
}

struct OfficialHistoryComponent {
    let id: String
    let name: String
    let hidden: Bool
    let displayUptime: Bool
    let dataAvailableSince: String?
    let uptimePercent: Double?
    let timelineSource: OfficialTimelineSource
}

enum OfficialTimelineSource {
    case impacts([OfficialComponentImpact])
    case colors([String])
}

extension OfficialHistoryComponent {
    var impacts: [OfficialComponentImpact] {
        switch timelineSource {
        case .impacts(let impacts):
            return impacts
        case .colors:
            return []
        }
    }

    var fills: [String] {
        switch timelineSource {
        case .impacts:
            return []
        case .colors(let fills):
            return fills
        }
    }
}

struct OpenAIOfficialSummary: Decodable {
    let structure: Structure

    struct Structure: Decodable {
        let items: [Item]
    }

    struct Item: Decodable {
        let group: Group?
    }

    struct Group: Decodable {
        let id: String
        let name: String
        let hidden: Bool
        let displayAggregatedUptime: Bool?
        let components: [GroupComponent]
    }

    struct GroupComponent: Decodable {
        let componentId: String
        let hidden: Bool
        let displayUptime: Bool?
        let name: String
        let dataAvailableSince: String?
    }
}

struct OpenAIOfficialHistoryData: Decodable {
    let componentImpacts: [OfficialComponentImpact]
    let componentUptimes: [OfficialComponentUptime]

    var impactsByComponentID: [String: [OfficialComponentImpact]] {
        Dictionary(grouping: componentImpacts, by: \.componentId)
    }

    var uptimeByComponentID: [String: Double] {
        Dictionary(
            uniqueKeysWithValues: componentUptimes.compactMap { uptime in
                guard let componentID = uptime.componentId,
                      let percentage = uptime.uptimePercent else {
                    return nil
                }
                return (componentID, percentage)
            }
        )
    }

    var uptimeByGroupID: [String: Double] {
        Dictionary(
            uniqueKeysWithValues: componentUptimes.compactMap { uptime in
                guard let groupID = uptime.statusPageComponentGroupId,
                      let percentage = uptime.uptimePercent else {
                    return nil
                }
                return (groupID, percentage)
            }
        )
    }
}

struct OfficialComponentImpact: Decodable {
    let componentId: String
    let endAt: String?
    let startAt: String
    let status: OfficialImpactStatus
    let statusPageIncidentId: String?

    var timelineLevel: TimelineDayLevel {
        status.timelineLevel
    }

    var componentStatus: ComponentStatus {
        status.componentStatus
    }

    func isActive(at now: Date) -> Bool {
        guard let startAt = ComponentTimeline.parseISODate(startAt), startAt <= now else {
            return false
        }
        if let endAt, let resolvedAt = ComponentTimeline.parseISODate(endAt), resolvedAt < now {
            return false
        }
        return true
    }
}

struct OfficialComponentUptime: Decodable {
    let componentId: String?
    let statusPageComponentGroupId: String?
    let uptime: String

    var uptimePercent: Double? {
        Double(uptime)
    }
}

enum OfficialImpactStatus: String, Decodable {
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case fullOutage = "full_outage"
    case underMaintenance = "under_maintenance"

    var timelineLevel: TimelineDayLevel {
        switch self {
        case .degradedPerformance: .degraded
        case .underMaintenance: .maintenance
        case .partialOutage: .partialOutage
        case .fullOutage: .majorOutage
        }
    }

    var componentStatus: ComponentStatus {
        switch self {
        case .degradedPerformance: .degradedPerformance
        case .underMaintenance: .underMaintenance
        case .partialOutage: .partialOutage
        case .fullOutage: .majorOutage
        }
    }
}
