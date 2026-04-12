import AppKit
import SwiftUI

private enum MenuContentSizing {
    static let width: CGFloat = 360
    static let minScreenMargin: CGFloat = 140
}

enum MenuSelection: Hashable {
    case provider(ProviderConfig)
    case benchmark
}

struct StatusMenuContentView: View {
    let store: StatusStore
    let benchmarkStore: AIStupidLevelStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: MenuSelection?
    @State private var contentHeights: [MenuSelection: CGFloat] = [:]
    @State private var tooltipState = TooltipState()
    @State private var tooltipHeight: CGFloat = 0
    @State private var initialMeasurementDone = false
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

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
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        if headerHeight > 0, footerHeight > 0 {
            return max(200, screenHeight - headerHeight - footerHeight - 20)
        }
        return max(200, screenHeight - MenuContentSizing.minScreenMargin)
    }

    private var scrollFrameHeight: CGFloat {
        guard let measured = contentHeights[activeSelection] else {
            return maxVisibleContentHeight
        }
        return min(measured, maxVisibleContentHeight)
    }

    private var activeErrorMessage: String? {
        switch activeSelection {
        case .benchmark:
            benchmarkStore.errorMessage ?? store.errorMessage
        case .provider:
            store.errorMessage
        }
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
                .padding(.horizontal, 10)
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

            ScrollView {
                measuredContent
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: scrollFrameHeight)

            VStack(spacing: 0) {
                Divider()

                // Error message
                if let error = activeErrorMessage {
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
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let date = activeLastRefreshed {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = Int(context.date.timeIntervalSince(date))
                            Text("Updated \(seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min") ago")
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
                            .help("Refresh")
                            .modifier(FooterIconHover())
                        }

                        Button {
                            openWindow(id: "settings")
                            NSApp.activate(ignoringOtherApps: true)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")
                        .modifier(FooterIconHover())

                        Button {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            Image(systemName: "power")
                        }
                        .help("Quit")
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
        .frame(width: MenuContentSizing.width)
        .opacity(initialMeasurementDone ? 1 : 0)
        .coordinateSpace(name: "menu")
        .environment(tooltipState)
        .overlay(alignment: .topLeading) {
            if let info = tooltipState.info, info.details.contains(where: { $0.level != .operational && $0.level != .noData }) {
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
                        x: tooltipOffsetX(dayX: info.dayX),
                        y: max(0, y)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func tooltipOffsetX(dayX: CGFloat) -> CGFloat {
        let half: CGFloat = 110
        let pad: CGFloat = 8
        return min(max(pad, dayX - half), MenuContentSizing.width - half * 2 - pad)
    }

    private var measuredContent: some View {
        selectedProviderContent
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.height, initial: true) { _, h in
                            contentHeights[activeSelection] = h
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
                AIStupidLevelPageView(benchmarkStore: benchmarkStore) { provider in
                    selection = .provider(provider)
                }
            } else if benchmarkStore.isLoading {
                loadingPlaceholder
            } else {
                emptyPlaceholder(
                    message: benchmarkStore.errorMessage ?? "No benchmark data yet."
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
        placeholder(message: "Loading...", showsProgress: true)
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

// MARK: - Provider Tab Grid

private struct ProviderTabGrid: View {
    let providers: [ProviderConfig]
    let activeSelection: MenuSelection
    let summaries: [ProviderConfig: StatuspageSummary]
    let settings: SettingsStore
    let onSelectProvider: (ProviderConfig) -> Void
    let onSelectBenchmark: () -> Void

    private let columns = 3

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<providerRowCount, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = rowIndex * columns + col
                        if index < providers.count {
                            let provider = providers[index]
                            ProviderTab(
                                name: settings.displayName(for: provider),
                                isSelected: activeSelection == .provider(provider),
                                indicator: summaries[provider]?.status.indicator
                            ) {
                                onSelectProvider(provider)
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }

            Divider()
                .gridCellColumns(columns)
                .padding(.vertical, 2)

            GridRow {
                BenchmarkTab(
                    isSelected: activeSelection == .benchmark,
                    action: onSelectBenchmark
                )
                Color.clear
                    .frame(maxWidth: .infinity)
                    .gridCellUnsizedAxes(.vertical)
                Color.clear
                    .frame(maxWidth: .infinity)
                    .gridCellUnsizedAxes(.vertical)
            }
        }
    }

    private var providerRowCount: Int {
        (providers.count + columns - 1) / columns
    }
}

// MARK: - Benchmark Tab

private struct BenchmarkTab: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10))
                Text("Benchmark")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
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

// MARK: - Provider Tab

struct ProviderTab: View {
    let name: String
    let isSelected: Bool
    let indicator: StatusIndicator?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
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
            .foregroundStyle(isSelected ? .primary : .secondary)
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
        .onHover { hovering in
            isHovered = hovering
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
