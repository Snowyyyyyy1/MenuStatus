import SwiftUI

private enum UptimeBarStyle {
    static let height: CGFloat = 22
    static let tooltipWidth: CGFloat = 220
}

// MARK: - Provider Section

struct ProviderSectionView: View {
    let provider: ProviderConfig
    let summary: StatuspageSummary?
    let store: StatusStore
    let settings: SettingsStore

    private var visibleComponents: [Component] {
        (summary?.components ?? []).filter { $0.group != true }
    }

    private var activeIncidents: [Incident] {
        (summary?.incidents ?? []).filter { $0.status.isActive }
    }

    private var groupedSections: [GroupedComponentSection] {
        store.sections(for: provider)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let summary {
                statusPageContent(summary: summary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusPageContent(summary: StatuspageSummary) -> some View {
        HStack {
            Label(summary.status.indicator.displayName, systemImage: summary.status.indicator.sfSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(summary.status.indicator.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        if !activeIncidents.isEmpty {
            ForEach(activeIncidents) { incident in
                IncidentRow(incident: incident)
            }
            .padding(.bottom, 4)
        }

        Divider()
            .padding(.horizontal, 16)

        if groupedSections.isEmpty {
            ForEach(visibleComponents) { component in
                ComponentUptimeRow(
                    component: component,
                    timeline: store.timeline(for: provider, componentId: component.id),
                    dayDetails: store.dayDetails(for: provider, componentId: component.id),
                    statusPageURL: provider.statusPageURL
                )
            }
        } else {
            ForEach(groupedSections) { section in
                GroupHeaderView(
                    section: section,
                    isExpanded: store.isExpanded(section, provider: provider),
                    provider: provider,
                    store: store,
                    dayDetails: store.dayDetails(for: provider, section: section)
                )

                if store.isExpanded(section, provider: provider) {
                    ForEach(section.components) { component in
                        ComponentUptimeRow(
                            component: component,
                            timeline: store.timeline(for: provider, componentId: component.id),
                            dayDetails: store.dayDetails(for: provider, componentId: component.id),
                            statusPageURL: provider.statusPageURL,
                            contentPaddingLeading: 30
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Group Header

struct GroupHeaderView: View {
    let section: GroupedComponentSection
    let isExpanded: Bool
    let provider: ProviderConfig
    let store: StatusStore
    let dayDetails: [Date: [DayIncidentDetail]]

    @State private var isHovered = false

    var body: some View {
        Button {
            store.toggleExpansion(for: section, provider: provider)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .scaleEffect(isHovered ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)

                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("\(section.componentCount) component\(section.componentCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(section.status.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(section.status.color)
                }

                if let timeline = section.timeline {
                    UptimeBarWithLabels(timeline: timeline, dayDetails: dayDetails)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Component Uptime Row

struct ComponentUptimeRow: View {
    let component: Component
    let timeline: ComponentTimeline?
    let dayDetails: [Date: [DayIncidentDetail]]
    let statusPageURL: URL
    var contentPaddingLeading: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(component.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(component.status.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(component.status.color)
            }

            if let timeline {
                UptimeBarWithLabels(timeline: timeline, dayDetails: dayDetails)
            }
        }
        .padding(.leading, contentPaddingLeading)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(statusPageURL)
        }
    }
}

// MARK: - Uptime Bar

struct UptimeBarWithLabels: View {
    let timeline: ComponentTimeline
    let dayDetails: [Date: [DayIncidentDetail]]

    var body: some View {
        VStack(spacing: 0) {
            UptimeBarView(timeline: timeline, height: UptimeBarStyle.height, dayDetails: dayDetails)

            HStack {
                Text("90 days ago")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(timeline.hasMeasuredDays
                    ? String(format: "%@%.2f%% uptime", timeline.isEstimated ? "≈ " : "", timeline.uptimePercent)
                    : "No data")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Today")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct UptimeBarView: View {
    let timeline: ComponentTimeline
    let height: CGFloat
    let dayDetails: [Date: [DayIncidentDetail]]

    @Environment(TooltipState.self) private var tooltipState
    @State private var hoveredDayIndex: Int?

    var body: some View {
        Canvas { context, size in
            let count = timeline.days.count
            guard count > 0 else { return }
            let spacing: CGFloat = 1
            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = (size.width - totalSpacing) / CGFloat(count)

            for (index, day) in timeline.days.enumerated() {
                let x = CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: 0, width: barWidth, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(day.color))

                if index == hoveredDayIndex {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 1),
                                   with: .color(.white), lineWidth: 1.5)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            GeometryReader { proxy in
                let menuFrame = proxy.frame(in: .named("menu"))
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let count = timeline.days.count
                            guard count > 0 else { return }
                            let index = min(max(0, Int(point.x / proxy.size.width * CGFloat(count))), count - 1)
                            let day = timeline.days[index]
                            let details = dayDetails[day.date] ?? []
                            hoveredDayIndex = index

                            if !details.isEmpty && day.level != .operational && day.level != .noData {
                                let dayX = menuFrame.minX + (CGFloat(index) + 0.5) / CGFloat(count) * proxy.size.width
                                tooltipState.info = TooltipState.TooltipInfo(
                                    day: day,
                                    details: details,
                                    dayX: dayX,
                                    barMinY: menuFrame.minY,
                                    barMaxY: menuFrame.maxY
                                )
                            } else {
                                tooltipState.info = nil
                            }
                        case .ended:
                            hoveredDayIndex = nil
                            tooltipState.info = nil
                        }
                    }
            }
        }
    }
}

// MARK: - Day Detail Tooltip

struct DayDetailTooltip: View {
    let day: DayStatus
    let details: [DayIncidentDetail]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private var groupedDetails: [(level: TimelineDayLevel, totalSeconds: TimeInterval)] {
        var byLevel: [TimelineDayLevel: TimeInterval] = [:]
        for detail in details {
            byLevel[detail.level, default: 0] += detail.durationSeconds
        }
        return byLevel.sorted { $0.key > $1.key }.map { (level: $0.key, totalSeconds: $0.value) }
    }

    private var incidentNames: [String] {
        var seen = Set<String>()
        return details.compactMap(\.incidentName).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dateFormatter.string(from: day.date))
                .font(.system(size: 11, weight: .semibold))

            if !groupedDetails.isEmpty {
                ForEach(groupedDetails, id: \.level) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.level.color)
                            .frame(width: 6, height: 6)
                        Text(entry.level.displayName.capitalized)
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text(formatDuration(entry.totalSeconds))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if !incidentNames.isEmpty {
                    Divider()
                    Text("RELATED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    ForEach(incidentNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: UptimeBarStyle.tooltipWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours) hrs \(mins) mins"
        }
        return "\(max(1, mins)) mins"
    }
}

// MARK: - Incident Row

struct IncidentRow: View {
    let incident: Incident

    private var impact: StatusIndicator {
        incident.impact ?? .minor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(impact.impactColor)
                Text(incident.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if incident.impact != nil {
                    Text(impact.impactLabel.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(impact.impactColor.opacity(0.15))
                        .foregroundStyle(impact.impactColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }

            if let latestUpdate = incident.incidentUpdates?.first {
                Text(latestUpdate.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
