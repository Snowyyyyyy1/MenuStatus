import AppKit
import SwiftUI

enum MenuContentSizing {
    static let width: CGFloat = 360
    static let minScreenMargin: CGFloat = 140
    static let provisionalContentHeight: CGFloat = 320
}

enum MenuTabMetrics {
    static let minHeight: CGFloat = 30
}

enum MenuTabGridLayout {
    static let spacing: CGFloat = 4
    static let providerHorizontalPadding: CGFloat = 10
    static let maxRows: Int = 4
    static let minComfortableTabWidth: CGFloat = 60
    static let tabHorizontalPadding: CGFloat = 12
    static let tabInnerSpacing: CGFloat = 5
    static let statusDotWidth: CGFloat = 6
    static let tabTextFontSize: CGFloat = 13

    struct LayoutPlan: Equatable {
        let rowCount: Int
        let perRow: Int
        let uniformWidth: CGFloat
    }

    static func availableRowWidth(totalWidth: CGFloat = MenuContentSizing.width) -> CGFloat {
        max(0, totalWidth - providerHorizontalPadding * 2)
    }

    static func textWidth(
        _ text: String,
        fontSize: CGFloat = tabTextFontSize,
        weight: NSFont.Weight = .semibold
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Content width for a tab drawn with `MenuTabButton`. Measured in the widest
    /// (selected = semibold) state so layout is stable across selection changes.
    static func tabContentWidth(
        text: String,
        hasLeadingDot: Bool = false,
        leadingIconWidth: CGFloat = 0
    ) -> CGFloat {
        var total = textWidth(text) + tabHorizontalPadding
        if hasLeadingDot {
            total += statusDotWidth + tabInnerSpacing
        }
        if leadingIconWidth > 0 {
            total += leadingIconWidth + tabInnerSpacing
        }
        // Tiny slack to avoid last-pixel truncation in HiDPI rounding.
        return ceil(total + 2)
    }

    /// Pick a row count (1..maxRows) and a uniform per-tab width so that every tab
    /// has at least the comfortable minimum width and, when possible, room for its
    /// natural content. Uniform width fills the row (CodexBar-style expansion).
    static func resolveLayout(
        widths: [CGFloat],
        availableWidth: CGFloat,
        maxRows: Int = maxRows,
        minComfortableWidth: CGFloat = minComfortableTabWidth
    ) -> LayoutPlan {
        guard !widths.isEmpty, availableWidth > 0 else {
            return LayoutPlan(rowCount: 0, perRow: 0, uniformWidth: 0)
        }
        let count = widths.count
        let maxDesired = widths.max() ?? 0
        let effectiveMaxRows = min(maxRows, count)

        var chosenRows = effectiveMaxRows
        var chosenPerRow = Int(ceil(Double(count) / Double(effectiveMaxRows)))
        var chosenAllowed = (availableWidth - spacing * CGFloat(chosenPerRow - 1)) / CGFloat(chosenPerRow)

        for rows in 1...effectiveMaxRows {
            let perRow = Int(ceil(Double(count) / Double(rows)))
            let allowed = (availableWidth - spacing * CGFloat(max(0, perRow - 1))) / CGFloat(perRow)
            let fitsContent = allowed >= maxDesired
            let comfortable = allowed >= minComfortableWidth
            if fitsContent || (comfortable && rows == effectiveMaxRows) {
                chosenRows = rows
                chosenPerRow = perRow
                chosenAllowed = allowed
                break
            }
            if rows == effectiveMaxRows {
                chosenRows = rows
                chosenPerRow = perRow
                chosenAllowed = allowed
            }
        }

        let uniform = max(0, floor(chosenAllowed))
        return LayoutPlan(rowCount: chosenRows, perRow: chosenPerRow, uniformWidth: uniform)
    }

    static func rowRange(count: Int, perRow: Int, rowIndex: Int) -> Range<Int> {
        guard perRow > 0 else { return 0..<0 }
        let start = rowIndex * perRow
        let end = min(count, start + perRow)
        return start..<end
    }
}

enum MenuContentLayout {
    static func fallbackMeasuredHeight(
        lastMeasuredHeight: CGFloat?,
        usesLastMeasuredFallback: Bool
    ) -> CGFloat? {
        usesLastMeasuredFallback ? lastMeasuredHeight : nil
    }

    static func maxVisibleContentHeight(
        availablePopoverHeight: CGFloat?,
        fallbackScreenHeight: CGFloat,
        headerHeight: CGFloat,
        footerHeight: CGFloat,
        minimumContentHeight: CGFloat = 200,
        fallbackScreenMargin: CGFloat = MenuContentSizing.minScreenMargin,
        fallbackPopoverPadding: CGFloat = 20
    ) -> CGFloat {
        if let availablePopoverHeight {
            return max(minimumContentHeight, availablePopoverHeight - headerHeight - footerHeight)
        }

        if headerHeight > 0, footerHeight > 0 {
            return max(
                minimumContentHeight,
                fallbackScreenHeight - headerHeight - footerHeight - fallbackPopoverPadding
            )
        }

        return max(minimumContentHeight, fallbackScreenHeight - fallbackScreenMargin)
    }

    static func acceptedMeasuredContentHeight(
        previousMeasuredHeight: CGFloat?,
        newMeasuredHeight: CGFloat,
        minimumUsableHeight: CGFloat = 1
    ) -> CGFloat? {
        guard newMeasuredHeight > minimumUsableHeight else {
            return previousMeasuredHeight
        }

        return newMeasuredHeight
    }

    static func needsScroll(measuredHeight: CGFloat?, maxVisibleContentHeight: CGFloat) -> Bool {
        guard let measuredHeight else { return true }
        return measuredHeight >= maxVisibleContentHeight
    }

    static func scrollFrameHeight(measuredHeight: CGFloat?, maxVisibleContentHeight: CGFloat) -> CGFloat {
        guard let measuredHeight else { return maxVisibleContentHeight }
        return min(measuredHeight, maxVisibleContentHeight)
    }

    static func provisionalScrollFrameHeight(
        measuredHeight: CGFloat?,
        lastMeasuredHeight: CGFloat?,
        maxVisibleContentHeight: CGFloat,
        defaultContentHeight: CGFloat = MenuContentSizing.provisionalContentHeight
    ) -> CGFloat {
        if let measuredHeight {
            return scrollFrameHeight(
                measuredHeight: measuredHeight,
                maxVisibleContentHeight: maxVisibleContentHeight
            )
        }

        if let lastMeasuredHeight {
            return min(lastMeasuredHeight, maxVisibleContentHeight)
        }

        return min(defaultContentHeight, maxVisibleContentHeight)
    }

    static func visibleContentHeight(
        measuredHeight: CGFloat?,
        lastMeasuredHeight: CGFloat?,
        maxVisibleContentHeight: CGFloat,
        defaultContentHeight: CGFloat = MenuContentSizing.provisionalContentHeight
    ) -> CGFloat {
        if let measuredHeight, measuredHeight < maxVisibleContentHeight {
            return measuredHeight
        }

        return provisionalScrollFrameHeight(
            measuredHeight: measuredHeight,
            lastMeasuredHeight: lastMeasuredHeight,
            maxVisibleContentHeight: maxVisibleContentHeight,
            defaultContentHeight: defaultContentHeight
        )
    }

    static func preferredPopoverHeight(
        headerHeight: CGFloat,
        footerHeight: CGFloat,
        measuredContentHeight: CGFloat?,
        lastMeasuredContentHeight: CGFloat?,
        maxVisibleContentHeight: CGFloat,
        defaultContentHeight: CGFloat = MenuContentSizing.provisionalContentHeight
    ) -> CGFloat {
        headerHeight + footerHeight + visibleContentHeight(
            measuredHeight: measuredContentHeight,
            lastMeasuredHeight: lastMeasuredContentHeight,
            maxVisibleContentHeight: maxVisibleContentHeight,
            defaultContentHeight: defaultContentHeight
        )
    }

    static func shouldRequestPopoverResize(
        headerHeight: CGFloat,
        footerHeight: CGFloat,
        initialMeasurementDone: Bool
    ) -> Bool {
        initialMeasurementDone && headerHeight > 0 && footerHeight > 0
    }
}

enum MenuLayoutMetrics {
    static func tooltipOffsetX(
        dayX: CGFloat,
        menuWidth: CGFloat,
        tooltipWidth: CGFloat = 220,
        padding: CGFloat = 8
    ) -> CGFloat {
        let maxOffset = max(padding, menuWidth - tooltipWidth - padding)
        return min(max(padding, dayX - tooltipWidth / 2), maxOffset)
    }
}

struct MenuErrorMessages: Equatable {
    let inline: String?
    let footer: String?
}

enum MenuErrorPresentation {
    static func messages(
        for selection: MenuSelection,
        statusError: String?,
        benchmarkError: String?
    ) -> MenuErrorMessages {
        switch selection {
        case .benchmark:
            return MenuErrorMessages(
                inline: benchmarkError ?? statusError,
                footer: nil
            )
        case .provider:
            return MenuErrorMessages(
                inline: nil,
                footer: statusError
            )
        }
    }
}

enum MenuSelection: Hashable {
    case provider(ProviderConfig)
    case benchmark
}

struct BenchmarkSectionExpansionState {
    var globalIndex = true
    var ranking = true
    var vendorComparison = false
    var recommendations = false
    var alerts = false
    var degradations = false
}

struct StatusMenuContentView: View {
    let store: StatusStore
    let benchmarkStore: AIStupidLevelStore
    let hostCoordinator: MenuHostCoordinator
    @Environment(\.locale) private var locale
    @State private var selection: MenuSelection?
    @State private var contentHeights: [MenuSelection: CGFloat] = [:]
    @State private var tooltipState = TooltipState()
    @State private var tooltipHeight: CGFloat = 0
    @State private var benchmarkHoverInfo: BenchmarkRowHoverInfo?
    @State private var pendingBenchmarkHoverInfo: BenchmarkRowHoverInfo?
    @State private var benchmarkHoverHeight: CGFloat = 0
    @State private var benchmarkHoverTask: Task<Void, Never>?
    @State private var benchmarkSections = BenchmarkSectionExpansionState()
    @State private var initialMeasurementDone = false
    @State private var lastMeasuredContentHeight: CGFloat?
    @State private var pendingSelectionMeasurement: MenuSelection?
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var measuredMenuWidth: CGFloat = MenuContentSizing.width

    private var enabledProviders: [ProviderConfig] {
        store.settings.providerConfigs.enabledProviders(settings: store.settings)
    }

    private var activeSelection: MenuSelection {
        if let selection {
            switch selection {
            case .provider(let p) where enabledProviders.contains(p):
                return selection
            case .benchmark:
                return selection
            default:
                break
            }
        }
        if let first = enabledProviders.first {
            return .provider(first)
        }
        return .benchmark
    }

    private var maxVisibleContentHeight: CGFloat {
        MenuContentLayout.maxVisibleContentHeight(
            availablePopoverHeight: hostCoordinator.availablePopoverHeight,
            fallbackScreenHeight: NSScreen.main?.visibleFrame.height ?? 900,
            headerHeight: headerHeight,
            footerHeight: footerHeight
        )
    }

    private var activeContentHeight: CGFloat? {
        contentHeights[activeSelection]
    }

    private var needsScroll: Bool {
        MenuContentLayout.needsScroll(
            measuredHeight: activeContentHeight,
            maxVisibleContentHeight: maxVisibleContentHeight
        )
    }

    private var scrollFrameHeight: CGFloat {
        MenuContentLayout.provisionalScrollFrameHeight(
            measuredHeight: activeContentHeight,
            lastMeasuredHeight: fallbackMeasuredContentHeight,
            maxVisibleContentHeight: maxVisibleContentHeight
        )
    }

    private var preferredPopoverHeight: CGFloat {
        MenuContentLayout.preferredPopoverHeight(
            headerHeight: headerHeight,
            footerHeight: footerHeight,
            measuredContentHeight: activeContentHeight,
            lastMeasuredContentHeight: fallbackMeasuredContentHeight,
            maxVisibleContentHeight: maxVisibleContentHeight
        )
    }

    private var fallbackMeasuredContentHeight: CGFloat? {
        MenuContentLayout.fallbackMeasuredHeight(
            lastMeasuredHeight: lastMeasuredContentHeight,
            usesLastMeasuredFallback: pendingSelectionMeasurement == activeSelection
        )
    }

    private var activeErrorMessages: MenuErrorMessages {
        MenuErrorPresentation.messages(
            for: activeSelection,
            statusError: store.errorMessage,
            benchmarkError: benchmarkStore.errorMessage
        )
    }

    private var activeLastRefreshed: Date? {
        switch activeSelection {
        case .benchmark:
            benchmarkStore.lastRefreshed
        case .provider:
            store.lastRefreshed
        }
    }

    private var activeIsLoading: Bool {
        switch activeSelection {
        case .benchmark:
            benchmarkStore.isLoading || store.isLoading
        case .provider:
            store.isLoading
        }
    }

    private var activeBenchmarkHoverScore: BenchmarkScore? {
        guard let hover = benchmarkHoverInfo else { return nil }
        return benchmarkStore.scores.first(where: { $0.id == hover.score.id }) ?? hover.score
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar (3-column grid)
            VStack(spacing: 0) {
                ProviderTabGrid(
                    providers: enabledProviders,
                    activeSelection: activeSelection,
                    summaries: store.summaries,
                    settings: store.settings,
                    onSelectProvider: { provider in
                        selection = .provider(provider)
                    },
                    onSelectBenchmark: {
                        selection = .benchmark
                    }
                )
                .padding(.horizontal, MenuTabGridLayout.providerHorizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider()
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.height, initial: true) { _, h in headerHeight = h }
                }
            }

            if needsScroll {
                ScrollView {
                    measuredContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .frame(height: scrollFrameHeight)
            } else {
                measuredContent
            }

            VStack(spacing: 0) {
                Divider()

                // Error message
                if let error = activeErrorMessages.footer {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }

                // Footer
                HStack {
                    if !store.isConnected {
                        Label("menu.offline", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let date = activeLastRefreshed {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(AppStrings.updatedString(
                                since: date,
                                referenceDate: context.date,
                                locale: locale
                            ))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()

                    HStack(spacing: 12) {
                        if activeIsLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Button {
                                Task { await refreshVisibleContent() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help(AppStrings.localizedString(
                                "menu.footer.refresh.help",
                                locale: locale,
                                defaultValue: "Refresh"
                            ))
                            .focusable(false)
                            .modifier(FooterIconHover())
                        }

                        Button {
                            hostCoordinator.openSettings()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help(AppStrings.localizedString(
                            "menu.footer.settings.help",
                            locale: locale,
                            defaultValue: "Settings"
                        ))
                        .focusable(false)
                        .modifier(FooterIconHover())

                        Button {
                            hostCoordinator.quit()
                        } label: {
                            Image(systemName: "power")
                        }
                        .help(AppStrings.localizedString(
                            "menu.footer.quit.help",
                            locale: locale,
                            defaultValue: "Quit"
                        ))
                        .focusable(false)
                        .modifier(FooterIconHover())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                }
                .padding(10)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.height, initial: true) { _, h in footerHeight = h }
                }
            }
        }
        .frame(width: MenuContentSizing.width, alignment: .topLeading)
        .opacity(initialMeasurementDone ? 1 : 0)
        .coordinateSpace(name: "menu")
        .environment(tooltipState)
        .onChange(of: activeSelection) { _, newSelection in
            hostCoordinator.selectionDidChange()
            pendingSelectionMeasurement = newSelection
            if case .benchmark = newSelection {
                return
            }
            benchmarkHoverTask?.cancel()
            pendingBenchmarkHoverInfo = nil
            benchmarkHoverInfo = nil
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, width in
                        measuredMenuWidth = width
                    }
            }
        }
        .onChange(of: preferredPopoverHeight, initial: true) { _, height in
            guard MenuContentLayout.shouldRequestPopoverResize(
                headerHeight: headerHeight,
                footerHeight: footerHeight,
                initialMeasurementDone: initialMeasurementDone
            ) else {
                return
            }
            guard height > 0 else { return }
            hostCoordinator.requestPopoverResize(height)
        }
        .overlay(alignment: .topLeading) {
            if case .benchmark = activeSelection,
               let hover = benchmarkHoverInfo,
               let score = activeBenchmarkHoverScore {
                let pad: CGFloat = 8
                let showBelow = hover.rowMinY < (benchmarkHoverHeight + pad * 2)
                let y = showBelow ? hover.rowMaxY + pad : hover.rowMinY - benchmarkHoverHeight - pad

                BenchmarkModelHoverCard(
                    score: score,
                    detail: benchmarkStore.modelDetailsByID[score.id],
                    stats: benchmarkStore.modelStatsByModelID[score.id],
                    history: benchmarkStore.historyByModelID[score.id]
                )
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.size.height, initial: true) { _, h in benchmarkHoverHeight = h }
                    }
                }
                .offset(
                    x: MenuLayoutMetrics.tooltipOffsetX(
                        dayX: hover.anchorX,
                        menuWidth: measuredMenuWidth,
                        tooltipWidth: HoverSurfaceStyle.renderedWidth(forContentWidth: BenchmarkHoverStyle.tooltipWidth)
                    ),
                    y: max(0, y)
                )
                .allowsHitTesting(false)
            } else if let info = tooltipState.info, info.details.contains(where: { $0.level != .operational && $0.level != .noData }) {
                let pad: CGFloat = 8
                let showBelow = info.barMinY < (tooltipHeight + pad * 2)
                let y = showBelow ? info.barMaxY + pad : info.barMinY - tooltipHeight - pad

                DayDetailTooltip(day: info.day, details: info.details)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: proxy.size.height, initial: true) { _, h in tooltipHeight = h }
                        }
                    }
                    .offset(
                        x: MenuLayoutMetrics.tooltipOffsetX(
                            dayX: info.dayX,
                            menuWidth: measuredMenuWidth,
                            tooltipWidth: HoverSurfaceStyle.renderedWidth(forContentWidth: UptimeBarStyle.tooltipWidth)
                        ),
                        y: max(0, y)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private var measuredContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = activeErrorMessages.inline {
                InlineMenuErrorBanner(message: error)
            }

            selectedProviderContent
        }
        .id(activeSelection)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, h in
                        guard let acceptedHeight = MenuContentLayout.acceptedMeasuredContentHeight(
                            previousMeasuredHeight: contentHeights[activeSelection],
                            newMeasuredHeight: h
                        ) else {
                            return
                        }

                        contentHeights[activeSelection] = acceptedHeight
                        lastMeasuredContentHeight = acceptedHeight
                        if pendingSelectionMeasurement == activeSelection {
                            pendingSelectionMeasurement = nil
                        }
                        if !initialMeasurementDone { initialMeasurementDone = true }
                    }
            }
        }
    }

    @ViewBuilder
    private var selectedProviderContent: some View {
        switch activeSelection {
        case .benchmark:
            if benchmarkStore.hasVisibleContent {
                AIStupidLevelPageView(
                    benchmarkStore: benchmarkStore,
                    sections: $benchmarkSections,
                    availableProviders: enabledProviders,
                    onNavigateToProvider: { provider in
                        benchmarkHoverTask?.cancel()
                        pendingBenchmarkHoverInfo = nil
                        benchmarkHoverInfo = nil
                        selection = .provider(provider)
                    },
                    onHoverChange: { hoverInfo in
                        benchmarkHoverTask?.cancel()
                        pendingBenchmarkHoverInfo = hoverInfo

                        guard let hoverInfo else {
                            benchmarkHoverInfo = nil
                            return
                        }

                        let modelId = hoverInfo.score.id
                        if benchmarkStore.hasResolvedHoverPayload(for: modelId) {
                            benchmarkHoverInfo = hoverInfo
                            return
                        }

                        benchmarkHoverInfo = nil
                        benchmarkHoverTask = Task {
                            await benchmarkStore.loadHoverDataIfNeeded(modelId: modelId)
                            guard !Task.isCancelled else { return }

                            await MainActor.run {
                                guard case .benchmark = activeSelection,
                                      pendingBenchmarkHoverInfo?.score.id == modelId,
                                      benchmarkStore.hasResolvedHoverPayload(for: modelId)
                                else {
                                    return
                                }

                                benchmarkHoverInfo = pendingBenchmarkHoverInfo
                            }
                        }
                    }
                )
            } else if benchmarkStore.isLoading {
                loadingPlaceholder
            } else {
                emptyPlaceholder(
                    message: AppStrings.localizedString(
                        "menu.placeholder.no-benchmark",
                        locale: locale,
                        defaultValue: "No benchmark data yet."
                    )
                )
            }
        case .provider(let provider):
            if let summary = store.summaries[provider] {
                ProviderSectionView(
                    provider: provider,
                    summary: summary,
                    store: store,
                    settings: store.settings
                )
            } else {
                loadingPlaceholder
            }
        }
    }

    private var loadingPlaceholder: some View {
        placeholder(
            message: AppStrings.localizedString(
                "menu.placeholder.loading",
                locale: locale,
                defaultValue: "Loading..."
            ),
            showsProgress: true
        )
    }

    private func emptyPlaceholder(message: String) -> some View {
        placeholder(message: message, showsProgress: false)
    }

    private func placeholder(message: String, showsProgress: Bool) -> some View {
        VStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func refreshVisibleContent() async {
        async let providerRefresh: Void = store.refreshNow()
        switch activeSelection {
        case .benchmark:
            async let benchmarkRefresh: Void = benchmarkStore.refreshNow()
            _ = await (providerRefresh, benchmarkRefresh)
        case .provider:
            _ = await providerRefresh
        }
    }
}

private struct InlineMenuErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.red.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct MenuTabButton<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: MenuTabMetrics.minHeight, alignment: .leading)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : isHovered ? Color.primary.opacity(0.05) : .clear)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

struct MenuGridPlaceholderCell: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .gridCellUnsizedAxes(.vertical)
    }
}

struct MenuCollapsibleHeader<RowContent: View, BelowContent: View>: View {
    let isExpanded: Bool
    let action: () -> Void
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let contentSpacing: CGFloat
    @ViewBuilder let rowContent: () -> RowContent
    @ViewBuilder let belowContent: () -> BelowContent

    @State private var isHovered = false

    init(
        isExpanded: Bool,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 8,
        contentSpacing: CGFloat = 8,
        action: @escaping () -> Void,
        @ViewBuilder rowContent: @escaping () -> RowContent,
        @ViewBuilder belowContent: @escaping () -> BelowContent
    ) {
        self.isExpanded = isExpanded
        self.action = action
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.contentSpacing = contentSpacing
        self.rowContent = rowContent
        self.belowContent = belowContent
    }

    init(
        isExpanded: Bool,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 8,
        contentSpacing: CGFloat = 8,
        action: @escaping () -> Void,
        @ViewBuilder rowContent: @escaping () -> RowContent
    ) where BelowContent == EmptyView {
        self.init(
            isExpanded: isExpanded,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            contentSpacing: contentSpacing,
            action: action,
            rowContent: rowContent,
            belowContent: { EmptyView() }
        )
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .scaleEffect(isHovered ? 1.2 : 1.0)

                    rowContent()
                }

                belowContent()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Provider Tab Grid

private struct ProviderTabGrid: View {
    let providers: [ProviderConfig]
    let activeSelection: MenuSelection
    let summaries: [ProviderConfig: StatuspageSummary]
    let settings: SettingsStore
    let onSelectProvider: (ProviderConfig) -> Void
    let onSelectBenchmark: () -> Void

    @Environment(\.locale) private var locale

    private var benchmarkLabel: String {
        AppStrings.localizedString(
            "menu.tab.benchmark",
            locale: locale,
            defaultValue: "Benchmark"
        )
    }

    var body: some View {
        let availableWidth = MenuTabGridLayout.availableRowWidth()
        let providerWidths = providers.map { provider in
            MenuTabGridLayout.tabContentWidth(
                text: settings.displayName(for: provider),
                hasLeadingDot: summaries[provider]?.status.indicator != nil
            )
        }
        let benchmarkWidth = MenuTabGridLayout.tabContentWidth(
            text: benchmarkLabel,
            leadingIconWidth: MenuTabGridLayout.statusDotWidth + 4
        )
        let combinedWidths = providerWidths + [benchmarkWidth]
        let plan = MenuTabGridLayout.resolveLayout(
            widths: combinedWidths,
            availableWidth: availableWidth
        )

        VStack(alignment: .leading, spacing: MenuTabGridLayout.spacing) {
            ForEach(0..<plan.rowCount, id: \.self) { rowIndex in
                let range = MenuTabGridLayout.rowRange(
                    count: providers.count,
                    perRow: plan.perRow,
                    rowIndex: rowIndex
                )
                if !range.isEmpty {
                    HStack(spacing: MenuTabGridLayout.spacing) {
                        ForEach(range, id: \.self) { index in
                            let provider = providers[index]
                            ProviderTab(
                                name: settings.displayName(for: provider),
                                isSelected: activeSelection == .provider(provider),
                                indicator: summaries[provider]?.status.indicator
                            ) {
                                onSelectProvider(provider)
                            }
                            .frame(width: plan.uniformWidth, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Divider()
                .padding(.vertical, 2)

            HStack(spacing: MenuTabGridLayout.spacing) {
                BenchmarkTab(
                    isSelected: activeSelection == .benchmark,
                    action: onSelectBenchmark
                )
                .frame(width: plan.uniformWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Benchmark Tab

private struct BenchmarkTab: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        MenuTabButton(isSelected: isSelected, action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10))
                Text("menu.tab.benchmark")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Provider Tab

struct ProviderTab: View {
    let name: String
    let isSelected: Bool
    let indicator: StatusIndicator?
    let action: () -> Void

    var body: some View {
        MenuTabButton(isSelected: isSelected, action: action) {
            HStack(spacing: 5) {
                if let indicator {
                    Circle()
                        .fill(indicator.color)
                        .frame(width: 6, height: 6)
                }
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Footer Icon Hover

private struct FooterIconHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isHovered ? .primary : .secondary)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
