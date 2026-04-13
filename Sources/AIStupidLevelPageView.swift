import SwiftUI

struct AIStupidLevelPageView: View {
    let benchmarkStore: AIStupidLevelStore
    let onNavigateToProvider: (ProviderConfig) -> Void

    @State private var globalIndexExpanded = true
    @State private var rankingExpanded = true
    @State private var vendorComparisonExpanded = false
    @State private var recommendationsExpanded = false
    @State private var alertsExpanded = false
    @State private var degradationsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = benchmarkStore.globalIndex {
                CollapsibleSection(
                    title: "Global Index",
                    isExpanded: $globalIndexExpanded
                ) {
                    GlobalIndexDetailView(
                        index: index,
                        batchStatus: benchmarkStore.batchStatus
                    )
                }
            }

            if !benchmarkStore.scores.isEmpty {
                CollapsibleSection(
                    title: "Model Ranking",
                    isExpanded: $rankingExpanded
                ) {
                    ModelRankingView(
                        scores: benchmarkStore.scores,
                        historyByModelID: benchmarkStore.historyByModelID,
                        onLoadHistory: { benchmarkStore.loadHistoryIfNeeded(modelId: $0) }
                    )
                }
            }

            vendorComparisonSection
            recommendationsSection
            alertsSection
            degradationsSection
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var vendorComparisonSection: some View {
        let rows = benchmarkStore.providerReliability
        if !rows.isEmpty {
            CollapsibleSection(
                title: "Vendor Comparison",
                isExpanded: $vendorComparisonExpanded
            ) {
                VendorComparisonView(
                    reliability: rows,
                    scores: benchmarkStore.scores,
                    onSelectVendor: { vendorName in
                        if let provider = findProvider(forVendor: vendorName) {
                            onNavigateToProvider(provider)
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if let recs = benchmarkStore.recommendations,
           recs.bestForCode != nil || recs.mostReliable != nil || recs.fastestResponse != nil {
            CollapsibleSection(
                title: "Recommendations",
                isExpanded: $recommendationsExpanded
            ) {
                RecommendationsView(recommendations: recs)
            }
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        let alerts = benchmarkStore.dashboardAlerts
        if !alerts.isEmpty {
            CollapsibleSection(
                title: "Alerts",
                isExpanded: $alertsExpanded,
                badge: alerts.count
            ) {
                AlertsListView(alerts: alerts)
            }
        }
    }

    @ViewBuilder
    private var degradationsSection: some View {
        let items = benchmarkStore.degradations
        if !items.isEmpty {
            CollapsibleSection(
                title: "Degradations",
                isExpanded: $degradationsExpanded,
                badge: items.count
            ) {
                DegradationsListView(degradations: items)
            }
        }
    }

    private func findProvider(forVendor vendorName: String) -> ProviderConfig? {
        ProviderConfig.builtInProviders.first {
            $0.aiStupidLevelVendor?.caseInsensitiveCompare(vendorName) == .orderedSame
        }
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let badge: Int?
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    init(
        title: String,
        isExpanded: Binding<Bool>,
        badge: Int? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.badge = badge
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .scaleEffect(isHovered ? 1.2 : 1.0)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider().padding(.horizontal, 12)
        }
    }
}

// MARK: - Section 1: Global Index Detail

private struct GlobalIndexDetailView: View {
    let index: GlobalIndex
    let batchStatus: DashboardBatchStatusData?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(Int(index.current.globalScore.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Image(systemName: trendSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(trendColor)

                Text(index.trend.capitalized)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                if let totalModels = index.totalModels {
                    Text("\(totalModels) models")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            LargeIndexChart(points: index.history.reversed())
                .frame(height: 60)

            if let nextRun = formattedNextRun {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("Next benchmark: \(nextRun)")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var trendColor: Color {
        switch index.trend {
        case "improving": return .green
        case "declining": return .red
        default: return .secondary
        }
    }

    private var trendSymbol: String {
        switch index.trend {
        case "improving": return "arrow.up"
        case "declining": return "arrow.down"
        default: return "arrow.right"
        }
    }

    private var formattedNextRun: String? {
        guard let raw = batchStatus?.nextScheduledRun else { return nil }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct LargeIndexChart: View {
    let points: [GlobalIndexPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let scores = points.map(\.globalScore)
            let minV = (scores.min() ?? 0) - 2
            let maxV = (scores.max() ?? 100) + 2
            let range = max(1, maxV - minV)

            var fillPath = Path()
            var linePath = Path()
            for (i, score) in scores.enumerated() {
                let x = CGFloat(i) / CGFloat(scores.count - 1) * size.width
                let y = size.height - CGFloat((score - minV) / range) * size.height
                if i == 0 {
                    fillPath.move(to: CGPoint(x: x, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                    linePath.move(to: CGPoint(x: x, y: y))
                } else {
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                    linePath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .color(.accentColor.opacity(0.1)))
            context.stroke(
                linePath,
                with: .color(.accentColor.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Section 2: Model Ranking

private struct ModelRankingView: View {
    let scores: [BenchmarkScore]
    let historyByModelID: [String: ModelHistoryPayload]
    let onLoadHistory: (String) -> Void

    @State private var vendorFilter: String?
    @State private var expandedModelID: String?

    private var orderedVendors: [String] {
        BenchmarkVendorPresentation.orderedVendorIDs(from: scores.map(\.provider))
    }

    private var filteredScores: [BenchmarkScore] {
        let sorted = scores.sorted { $0.currentScore > $1.currentScore }
        guard let filter = vendorFilter else { return sorted }
        return sorted.filter { $0.provider.caseInsensitiveCompare(filter) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BenchmarkVendorTabGrid(
                vendors: orderedVendors,
                selectedVendor: vendorFilter,
                onSelectAll: { vendorFilter = nil },
                onSelectVendor: { vendor in
                    vendorFilter = vendorFilter == vendor ? nil : vendor
                }
            )

            ForEach(Array(filteredScores.enumerated()), id: \.element.id) { rank, score in
                RankedModelRow(
                    rank: rank + 1,
                    score: score,
                    isExpanded: expandedModelID == score.id,
                    history: historyByModelID[score.id]
                ) {
                    if expandedModelID == score.id {
                        expandedModelID = nil
                    } else {
                        expandedModelID = score.id
                        onLoadHistory(score.id)
                    }
                }
            }
        }
    }
}

private struct BenchmarkVendorTabGrid: View {
    let vendors: [String]
    let selectedVendor: String?
    let onSelectAll: () -> Void
    let onSelectVendor: (String) -> Void

    private let columns = 3

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<rowCount, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<columns, id: \.self) { columnIndex in
                        let index = rowIndex * columns + columnIndex
                        if index == 0 {
                            BenchmarkVendorTab(
                                label: "All",
                                isSelected: selectedVendor == nil,
                                action: onSelectAll
                            )
                        } else {
                            let vendorIndex = index - 1
                            if vendorIndex < vendors.count {
                                let vendor = vendors[vendorIndex]
                                BenchmarkVendorTab(
                                    label: BenchmarkVendorPresentation.displayName(for: vendor),
                                    isSelected: selectedVendor?.caseInsensitiveCompare(vendor) == .orderedSame,
                                    action: { onSelectVendor(vendor) }
                                )
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .gridCellUnsizedAxes(.vertical)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowCount: Int {
        let itemCount = vendors.count + 1
        return (itemCount + columns - 1) / columns
    }
}

private struct BenchmarkVendorTab: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : isHovered ? Color.primary.opacity(0.05) : .clear)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct RankedModelRow: View {
    let rank: Int
    let score: BenchmarkScore
    let isExpanded: Bool
    let history: ModelHistoryPayload?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Text("#\(rank)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)

                    Text(score.name)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .leading)

                    VendorChip(vendor: score.provider)

                    ScoreBar(
                        score: score.currentScore,
                        lower: score.confidenceLower,
                        upper: score.confidenceUpper,
                        color: score.status.color
                    )
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)

                    Text("\(Int(score.currentScore.rounded()))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 22, alignment: .trailing)

                    Image(systemName: score.trend.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(score.trend.color)
                        .frame(width: 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let history {
                ModelHistorySparkline(points: history.history)
                    .frame(height: 20)
                    .padding(.leading, 32)
            }
        }
    }
}

struct VendorChip: View {
    let vendor: String

    var body: some View {
        Text(BenchmarkVendorPresentation.chipText(for: vendor))
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BenchmarkVendorPresentation.color(for: vendor))
            )
    }
}

// MARK: - Section 3: Vendor Comparison

private struct VendorComparisonView: View {
    let reliability: [ProviderReliabilityRow]
    let scores: [BenchmarkScore]
    let onSelectVendor: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sortedRows) { row in
                Button { onSelectVendor(row.provider) } label: {
                    HStack(spacing: 8) {
                        VendorChip(vendor: row.provider)

                        Text(BenchmarkVendorPresentation.displayName(for: row.provider))
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: 80, alignment: .leading)

                        let summary = vendorSummary(for: row.provider)
                        Text("\(summary.count) models")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text("avg \(Int(summary.avg.rounded()))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if let trust = row.trustScore {
                            Text("Trust \(trust)")
                                .font(.system(size: 10))
                                .foregroundStyle(trust >= 70 ? .green : trust >= 40 ? .yellow : .red)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortedRows: [ProviderReliabilityRow] {
        reliability.sorted { vendorSummary(for: $0.provider).avg > vendorSummary(for: $1.provider).avg }
    }

    private func vendorSummary(for vendor: String) -> (count: Int, avg: Double) {
        let matching = scores.filter { $0.provider.caseInsensitiveCompare(vendor) == .orderedSame }
        let avg = matching.isEmpty ? 0 : matching.map(\.currentScore).reduce(0, +) / Double(matching.count)
        return (matching.count, avg)
    }
}

// MARK: - Section 4: Recommendations

private struct RecommendationsView: View {
    let recommendations: AnalyticsRecommendationsPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let slot = recommendations.bestForCode {
                RecommendationCard(category: "Best for Code", icon: "curlybraces", slot: slot)
            }
            if let slot = recommendations.mostReliable {
                RecommendationCard(category: "Most Reliable", icon: "shield.lefthalf.filled", slot: slot)
            }
            if let slot = recommendations.fastestResponse {
                RecommendationCard(category: "Fastest Response", icon: "bolt.fill", slot: slot)
            }
        }
    }
}

private struct RecommendationCard: View {
    let category: String
    let icon: String
    let slot: AnalyticsRecommendationSlot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if let name = slot.name {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if let vendor = slot.vendor {
                        VendorChip(vendor: vendor)
                    }
                }
                if let reason = slot.reason {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let score = slot.score {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Section 5: Alerts

private struct AlertsListView: View {
    let alerts: [DashboardAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(alerts) { alert in
                HStack(spacing: 8) {
                    Image(systemName: severityIcon(alert.severity))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(severityColor(alert.severity))
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(BenchmarkVendorPresentation.displayName(for: alert.provider))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if let time = alert.detectedAt {
                                Text("· \(time)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func severityIcon(_ severity: String?) -> String {
        switch severity?.lowercased() {
        case "critical": return "xmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }

    private func severityColor(_ severity: String?) -> Color {
        switch severity?.lowercased() {
        case "critical": return .red
        case "warning": return .yellow
        default: return .blue
        }
    }
}

// MARK: - Section 6: Degradations

private struct DegradationsListView: View {
    let degradations: [AnalyticsDegradationItem]

    private var sorted: [AnalyticsDegradationItem] {
        degradations.sorted { ($0.dropPercentage ?? 0) > ($1.dropPercentage ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sorted) { item in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(item.modelName ?? "Unknown")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            if let vendor = item.provider {
                                VendorChip(vendor: vendor)
                            }
                        }
                        if let drop = item.dropPercentage {
                            HStack(spacing: 4) {
                                Text("↓\(String(format: "%.1f", drop))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                                if let current = item.currentScore, let baseline = item.baselineScore {
                                    Text("\(Int(current.rounded())) ← \(Int(baseline.rounded()))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}
