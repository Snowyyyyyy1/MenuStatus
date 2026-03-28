import SwiftUI

private enum UptimeBarStyle {
    static let height: CGFloat = 22
}

// MARK: - Provider Section

struct ProviderSectionView: View {
    let provider: Provider
    let summary: StatuspageSummary
    let store: StatusStore

    private var visibleComponents: [Component] {
        summary.components.filter { $0.group != true }
    }

    private var activeIncidents: [Incident] {
        (summary.incidents ?? []).filter { $0.status != "resolved" && $0.status != "postmortem" }
    }

    private var groupedSections: [GroupedComponentSection] {
        provider == .openAI ? store.sections(for: provider) : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Overall status header
            HStack {
                Label(summary.status.indicator.displayName, systemImage: summary.status.indicator.sfSymbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(summary.status.indicator.color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Active incidents
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
                        statusPageURL: provider.statusPageURL
                    )

                    if component.id != visibleComponents.last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            } else {
                ForEach(groupedSections) { section in
                    GroupedComponentSectionView(
                        section: section,
                        isExpanded: store.isExpanded(section),
                        store: store,
                        statusPageURL: provider.statusPageURL
                    )

                    if section.id != groupedSections.last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Grouped Component Section

struct GroupedComponentSectionView: View {
    let section: GroupedComponentSection
    let isExpanded: Bool
    let store: StatusStore
    let statusPageURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.toggleExpansion(for: section)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

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
                        UptimeBarView(timeline: timeline, height: UptimeBarStyle.height)

                        HStack {
                            Text("90 days ago")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(timeline.hasMeasuredDays ? String(format: "%.2f%% uptime", timeline.uptimePercent) : "No data")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Today")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(section.components) { component in
                        ComponentUptimeRow(
                            component: component,
                            timeline: store.timeline(for: .openAI, componentId: component.id),
                            statusPageURL: statusPageURL,
                            contentPaddingLeading: 30
                        )

                        if component.id != section.components.last?.id {
                            Divider()
                                .padding(.leading, 30)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}

// MARK: - Component Uptime Row

struct ComponentUptimeRow: View {
    let component: Component
    let timeline: ComponentTimeline?
    let statusPageURL: URL
    var contentPaddingLeading: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Component name + status
            HStack {
                Text(component.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(component.status.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(component.status.color)
            }

            // Uptime bar
            if let timeline {
                UptimeBarView(timeline: timeline, height: UptimeBarStyle.height)

                // Labels
                HStack {
                    Text("90 days ago")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(timeline.hasMeasuredDays ? String(format: "%.2f%% uptime", timeline.uptimePercent) : "No data")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Today")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
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

struct UptimeBarView: View {
    let timeline: ComponentTimeline
    let height: CGFloat

    var body: some View {
        HStack(spacing: 1) {
            ForEach(timeline.days) { day in
                RoundedRectangle(cornerRadius: 1)
                    .fill(day.color)
                    .frame(height: height)
                    .help(day.tooltip)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Incident Row

struct IncidentRow: View {
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(impactColor(incident.impact ?? "minor"))
                Text(incident.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if let impact = incident.impact {
                    Text(impact.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(impactColor(impact).opacity(0.15))
                        .foregroundStyle(impactColor(impact))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
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

    private func impactColor(_ impact: String) -> Color {
        switch impact {
        case "critical": .red
        case "major": .orange
        case "minor": .yellow
        default: .secondary
        }
    }
}
