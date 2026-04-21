import SwiftUI

struct AIStupidLevelPageView: View {
    let benchmarkStore: AIStupidLevelStore
    @Binding var sections: BenchmarkSectionExpansionState
    let availableProviders: [ProviderConfig]
    let onNavigateToProvider: (ProviderConfig) -> Void
    let onHoverChange: (BenchmarkRowHoverInfo?) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = benchmarkStore.globalIndex {
                CollapsibleSection(
                    title: AppStrings.localizedString(
                        "benchmark.section.global-index",
                        locale: locale,
                        defaultValue: "Global Index"
                    ),
                    isExpanded: $sections.globalIndex
                ) {
                    GlobalIndexDetailView(
                        index: index,
                        batchStatus: benchmarkStore.batchStatus
                    )
                }
            }

            if !benchmarkStore.scores.isEmpty {
                CollapsibleSection(
                    title: AppStrings.localizedString(
                        "benchmark.section.model-ranking",
                        locale: locale,
                        defaultValue: "Model Ranking"
                    ),
                    isExpanded: $sections.ranking
                ) {
                    ModelRankingView(
                        benchmarkStore: benchmarkStore,
                        scores: benchmarkStore.scores,
                        onHoverChange: onHoverChange
                    )
                }
            }

            vendorComparisonSection
            recommendationsSection
            alertsSection
            degradationsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)
        .onDisappear {
            onHoverChange(nil)
        }
    }

    @ViewBuilder
    private var vendorComparisonSection: some View {
        let rows = benchmarkStore.providerReliability
        if !rows.isEmpty {
            CollapsibleSection(
                title: AppStrings.localizedString(
                    "benchmark.section.vendor-comparison",
                    locale: locale,
                    defaultValue: "Vendor Comparison"
                ),
                isExpanded: $sections.vendorComparison
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
                title: AppStrings.localizedString(
                    "benchmark.section.recommendations",
                    locale: locale,
                    defaultValue: "Recommendations"
                ),
                isExpanded: $sections.recommendations
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
                title: AppStrings.localizedString(
                    "benchmark.section.alerts",
                    locale: locale,
                    defaultValue: "Alerts"
                ),
                isExpanded: $sections.alerts,
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
                title: AppStrings.localizedString(
                    "benchmark.section.degradations",
                    locale: locale,
                    defaultValue: "Degradations"
                ),
                isExpanded: $sections.degradations,
                badge: items.count
            ) {
                DegradationsListView(degradations: items)
            }
        }
    }

    private func findProvider(forVendor vendorName: String) -> ProviderConfig? {
        ProviderConfig.provider(matchingBenchmarkVendor: vendorName, in: availableProviders)
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let badge: Int?
    @ViewBuilder let content: () -> Content

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
            MenuCollapsibleHeader(
                isExpanded: isExpanded,
                action: { isExpanded.toggle() }
            ) {
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

            if isExpanded {
                content()
                    .padding(.horizontal, MenuTabGridLayout.sectionContentHorizontalPadding)
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
    @Environment(\.locale) private var locale

    private static let nextRunParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(index.current.globalScore.map { String(Int($0.rounded())) } ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Image(systemName: trendSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(trendColor)

                Text(AppStrings.localizedTrendName(index.trend, locale: locale))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                if let totalModels = index.totalModels {
                    Text(AppStrings.modelCountString(totalModels, locale: locale))
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
                    Text(AppStrings.nextBenchmarkString(nextRun, locale: locale))
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
        guard let date = Self.nextRunParser.date(from: raw) else { return raw }
        Self.relativeFormatter.locale = locale
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct LargeIndexChart: View {
    let points: [GlobalIndexPoint]

    var body: some View {
        Canvas { context, size in
            let numericPoints = points.enumerated().compactMap { index, point in
                point.globalScore.map { (index: index, value: $0) }
            }
            guard numericPoints.count >= 2 else { return }
            let hasGaps = numericPoints.count != points.count
            let scores = numericPoints.map(\.value)
            let minV = (scores.min() ?? 0) - 2
            let maxV = (scores.max() ?? 100) + 2
            let range = max(1, maxV - minV)

            if !hasGaps {
                var fillPath = Path()
                var linePath = Path()
                for point in numericPoints {
                    let x = CGFloat(point.index) / CGFloat(points.count - 1) * size.width
                    let y = size.height - CGFloat((point.value - minV) / range) * size.height
                    if point.index == 0 {
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
            } else {
                var linePath = Path()
                var hasOpenRun = false
                for (index, point) in points.enumerated() {
                    guard let score = point.globalScore else {
                        if hasOpenRun {
                            context.stroke(
                                linePath,
                                with: .color(.accentColor.opacity(0.7)),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                            )
                            linePath = Path()
                            hasOpenRun = false
                        }
                        continue
                    }

                    let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
                    let y = size.height - CGFloat((score - minV) / range) * size.height
                    if !hasOpenRun {
                        linePath.move(to: CGPoint(x: x, y: y))
                        hasOpenRun = true
                    } else {
                        linePath.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                if hasOpenRun {
                    context.stroke(
                        linePath,
                        with: .color(.accentColor.opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}

// MARK: - Section 2: Model Ranking

private struct ModelRankingView: View {
    let benchmarkStore: AIStupidLevelStore
    let scores: [BenchmarkScore]
    let onHoverChange: (BenchmarkRowHoverInfo?) -> Void
    @Environment(\.openURL) private var openURL

    @State private var vendorFilter: String?

    private var orderedVendors: [String] {
        BenchmarkVendorPresentation.orderedVendorIDs(from: scores.map(\.provider))
    }

    private var filteredScores: [BenchmarkScore] {
        let sorted = BenchmarkPresentationLogic.sortedScoresForRanking(scores)
        guard let filter = vendorFilter else { return sorted }
        return sorted.filter { BenchmarkVendorPresentation.matches($0.provider, filter) }
    }

    private var prefetchedModelIDs: [String] {
        Array(filteredScores.prefix(6).map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BenchmarkVendorTabGrid(
                vendors: orderedVendors,
                selectedVendor: vendorFilter,
                onSelectAll: { vendorFilter = nil },
                onSelectVendor: { vendor in
                    vendorFilter = BenchmarkVendorPresentation.matches(vendorFilter, vendor) ? nil : vendor
                }
            )

            ForEach(Array(filteredScores.enumerated()), id: \.element.id) { rank, score in
                RankedModelRow(
                    rank: rank + 1,
                    score: score,
                    onHoverChange: onHoverChange,
                    onSelect: { openModelDetail(for: score) }
                )
            }
        }
        .task(id: prefetchedModelIDs) {
            guard !prefetchedModelIDs.isEmpty else { return }
            await benchmarkStore.prefetchHoverDataIfNeeded(modelIDs: prefetchedModelIDs)
        }
    }

    private func openModelDetail(for score: BenchmarkScore) {
        guard let url = AIStupidLevelClient.modelDetailPageURL(modelId: score.id) else { return }
        openURL(url)
    }
}

private struct BenchmarkVendorTabGrid: View {
    let vendors: [String]
    let selectedVendor: String?
    let onSelectAll: () -> Void
    let onSelectVendor: (String) -> Void
    @Environment(\.locale) private var locale

    private var allLabel: String {
        AppStrings.localizedString(
            "benchmark.tab.all",
            locale: locale,
            defaultValue: "All"
        )
    }

    var body: some View {
        let availableWidth = MenuTabGridLayout.availableRowWidth(
            sideInset: MenuTabGridLayout.sectionContentHorizontalPadding
        )
        let labels = [allLabel] + vendors.map { BenchmarkVendorPresentation.displayName(for: $0) }
        let widths = labels.map { MenuTabGridLayout.tabContentWidth(text: $0) }
        let plan = MenuTabGridLayout.resolveLayout(
            widths: widths,
            availableWidth: availableWidth
        )

        VStack(alignment: .leading, spacing: MenuTabGridLayout.spacing) {
            ForEach(0..<plan.rowCount, id: \.self) { rowIndex in
                let range = MenuTabGridLayout.rowRange(
                    count: labels.count,
                    perRow: plan.perRow,
                    rowIndex: rowIndex
                )
                if !range.isEmpty {
                    HStack(spacing: MenuTabGridLayout.spacing) {
                        ForEach(range, id: \.self) { index in
                            tabView(at: index)
                                .frame(width: plan.uniformWidth, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tabView(at index: Int) -> some View {
        if index == 0 {
            BenchmarkVendorTab(
                label: allLabel,
                isSelected: selectedVendor == nil,
                action: onSelectAll
            )
        } else {
            let vendor = vendors[index - 1]
            BenchmarkVendorTab(
                label: BenchmarkVendorPresentation.displayName(for: vendor),
                isSelected: BenchmarkVendorPresentation.matches(selectedVendor, vendor),
                action: { onSelectVendor(vendor) }
            )
        }
    }
}

private struct BenchmarkVendorTab: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        MenuTabButton(isSelected: isSelected, action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct RankedModelRow: View {
    let rank: Int
    let score: BenchmarkScore
    let onHoverChange: (BenchmarkRowHoverInfo?) -> Void
    let onSelect: () -> Void

    @State private var rowFrame: CGRect = .zero
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
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

                Text(score.currentScore.map { String(Int($0.rounded())) } ?? "--")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: 22, alignment: .trailing)

                if score.currentScore != nil {
                    Image(systemName: score.trend.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(score.trend.color)
                        .frame(width: 10)
                } else {
                    Color.clear.frame(width: 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .named("menu")), initial: true) { _, frame in
                        rowFrame = frame
                        if isHovered {
                            emitHoverChange(frame: frame)
                        }
                    }
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                emitHoverChange(frame: rowFrame)
            } else {
                onHoverChange(nil)
            }
        }
        .onDisappear {
            isHovered = false
            onHoverChange(nil)
        }
    }

    private func emitHoverChange(frame: CGRect) {
        onHoverChange(
            BenchmarkRowHoverInfo(
                score: score,
                anchorX: frame.midX,
                rowMinY: frame.minY,
                rowMaxY: frame.maxY
            )
        )
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
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sortedRows) { row in
                Button { onSelectVendor(row.provider) } label: {
                    HStack(spacing: 8) {
                        VendorChip(vendor: row.provider)

                        Text(BenchmarkVendorPresentation.displayName(for: row.provider))
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: 80, alignment: .leading)

                        let summary = BenchmarkPresentationLogic.vendorSummary(for: row.provider, scores: scores)
                        Text(AppStrings.modelCountString(summary.count, locale: locale))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text(summary.averageScore.map { AppStrings.averageScoreString(Int($0.rounded()), locale: locale) } ?? "--")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if let trust = row.trustScore {
                            Text(AppStrings.trustString(trust, locale: locale))
                                .font(.system(size: 10))
                                .foregroundStyle(trust >= 70 ? .green : trust >= 40 ? .yellow : .red)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }

    private var sortedRows: [ProviderReliabilityRow] {
        reliability.sorted { lhs, rhs in
            let lhsSummary = BenchmarkPresentationLogic.vendorSummary(for: lhs.provider, scores: scores)
            let rhsSummary = BenchmarkPresentationLogic.vendorSummary(for: rhs.provider, scores: scores)
            switch (lhsSummary.averageScore, rhsSummary.averageScore) {
            case let (left?, right?):
                if left != right { return left > right }
                return lhs.provider < rhs.provider
            case (nil, nil):
                return lhs.provider < rhs.provider
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }

}

struct BenchmarkVendorSummary: Equatable {
    let count: Int
    let averageScore: Double?
}

enum BenchmarkPresentationLogic {
    static func sortedScoresForRanking(_ scores: [BenchmarkScore]) -> [BenchmarkScore] {
        scores.sorted { lhs, rhs in
            switch (lhs.currentScore, rhs.currentScore) {
            case let (left?, right?):
                if left != right { return left > right }
                return lhs.name < rhs.name
            case (nil, nil):
                return lhs.name < rhs.name
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }

    static func vendorSummary(for vendor: String, scores: [BenchmarkScore]) -> BenchmarkVendorSummary {
        let matching = scores.filter { BenchmarkVendorPresentation.matches($0.provider, vendor) }
        let values = matching.compactMap(\.currentScore)
        let averageScore = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return BenchmarkVendorSummary(count: matching.count, averageScore: averageScore)
    }
}

// MARK: - Section 4: Recommendations

private struct RecommendationsView: View {
    let recommendations: AnalyticsRecommendationsPayload
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let slot = recommendations.bestForCode {
                RecommendationCard(
                    category: AppStrings.localizedString(
                        "benchmark.recommendation.best-for-code",
                        locale: locale,
                        defaultValue: "Best for Code"
                    ),
                    icon: "curlybraces",
                    slot: slot
                )
            }
            if let slot = recommendations.mostReliable {
                RecommendationCard(
                    category: AppStrings.localizedString(
                        "benchmark.recommendation.most-reliable",
                        locale: locale,
                        defaultValue: "Most Reliable"
                    ),
                    icon: "shield.lefthalf.filled",
                    slot: slot
                )
            }
            if let slot = recommendations.fastestResponse {
                RecommendationCard(
                    category: AppStrings.localizedString(
                        "benchmark.recommendation.fastest-response",
                        locale: locale,
                        defaultValue: "Fastest Response"
                    ),
                    icon: "bolt.fill",
                    slot: slot
                )
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
    @Environment(\.locale) private var locale

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
                            Text(item.modelName ?? AppStrings.unknownLabel(locale: locale))
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
