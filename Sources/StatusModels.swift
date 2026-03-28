import Foundation
import SwiftUI

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

    var displayName: String {
        switch self {
        case .none: "Operational"
        case .minor: "Minor Issues"
        case .major: "Major Outage"
        case .critical: "Critical Outage"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none: "checkmark.circle.fill"
        case .minor: "exclamationmark.triangle.fill"
        case .major: "xmark.circle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: .green
        case .minor: .yellow
        case .major: .orange
        case .critical: .red
        }
    }

    private var severity: Int {
        switch self {
        case .none: 0
        case .minor: 1
        case .major: 2
        case .critical: 3
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

struct Incident: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let impact: String?
    let shortlink: String?
    let createdAt: String?
    let updatedAt: String?
    let incidentUpdates: [IncidentUpdate]?
    let components: [IncidentComponent]?
}

struct IncidentComponent: Codable {
    let id: String
    let name: String?
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

// MARK: - Incidents Response

struct IncidentsResponse: Codable {
    let incidents: [Incident]
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
    case operational
    case degraded
    case maintenance
    case partialOutage
    case majorOutage

    var color: Color {
        switch self {
        case .operational: .green
        case .degraded: .yellow
        case .maintenance: .blue
        case .partialOutage: .orange
        case .majorOutage: .red
        }
    }

    var displayName: String {
        switch self {
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

    static func build(incidents: [Incident], componentId: String, numDays: Int = 90) -> ComponentTimeline {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Find incidents affecting this component
        let relevant = incidents.filter { incident in
            // Check incident-level components
            if let comps = incident.components, comps.contains(where: { $0.id == componentId }) {
                return true
            }
            // Check incident_updates affected_components
            if let updates = incident.incidentUpdates {
                for update in updates {
                    if let affected = update.affectedComponents,
                       affected.contains(where: { $0.code == componentId }) {
                        return true
                    }
                }
            }
            return false
        }

        // Map days to worst impact
        var dayImpacts: [Date: String] = [:]
        for incident in relevant {
            guard let created = parseISODate(incident.createdAt) else { continue }
            let resolved = parseISODate(incident.updatedAt) ?? Date()
            let start = calendar.startOfDay(for: created)
            let end = calendar.startOfDay(for: resolved)

            var day = start
            while day <= end && day <= today {
                let newImpact = incident.impact ?? "minor"
                if severity(newImpact) > severity(dayImpacts[day] ?? "") {
                    dayImpacts[day] = newImpact
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"

        var affectedDays = 0
        let days: [DayStatus] = (0..<numDays).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let label = formatter.string(from: date)

            if let impact = dayImpacts[date] {
                affectedDays += 1
                let level: TimelineDayLevel = switch impact {
                case "critical": .majorOutage
                case "major": .partialOutage
                default: .degraded
                }
                return DayStatus(date: date, level: level, tooltip: "\(label): \(impact)")
            }
            return DayStatus(date: date, level: .operational, tooltip: "\(label): operational")
        }

        let uptime = Double(numDays - affectedDays) / Double(numDays) * 100.0
        return ComponentTimeline(days: days, uptimePercent: uptime)
    }

    static func buildFromImpacts(
        impacts: [OfficialComponentImpact],
        now: Date,
        numDays: Int = 90,
        uptimePercentOverride: Double? = nil,
        title: String
    ) -> ComponentTimeline {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
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

    private static func severity(_ impact: String) -> Int {
        switch impact {
        case "critical": 3
        case "major": 2
        case "minor": 1
        default: 0
        }
    }
}

enum OpenAIGroupID: String, CaseIterable, Identifiable {
    case apis
    case chatGPT
    case codex
    case sora
    case fedRAMP
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apis: "APIs"
        case .chatGPT: "ChatGPT"
        case .codex: "Codex"
        case .sora: "Sora"
        case .fedRAMP: "FedRAMP"
        case .other: "Other"
        }
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

struct OpenAIOfficialHistoryPayload {
    let generatedAt: Date?
    let summary: OpenAIOfficialSummary
    let data: OpenAIOfficialHistoryData
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
