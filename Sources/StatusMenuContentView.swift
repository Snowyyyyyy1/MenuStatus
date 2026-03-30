import AppKit
import SwiftUI

private enum MenuContentSizing {
    static let width: CGFloat = 360
    static let minScreenMargin: CGFloat = 140
}

struct StatusMenuContentView: View {
    let store: StatusStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedProvider: ProviderConfig?
    @State private var contentHeights: [ProviderConfig: CGFloat] = [:]
    @State private var tooltipState = TooltipState()
    @State private var tooltipHeight: CGFloat = 0

    private var enabledProviders: [ProviderConfig] {
        store.settings.providerConfigs.enabledProviders(settings: store.settings)
    }

    private var activeProvider: ProviderConfig? {
        if let selectedProvider, enabledProviders.contains(selectedProvider) {
            return selectedProvider
        }
        return enabledProviders.first
    }

    private var maxVisibleContentHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(200, screenHeight - MenuContentSizing.minScreenMargin)
    }

    private var activeContentHeight: CGFloat {
        guard let provider = activeProvider else { return .infinity }
        return contentHeights[provider] ?? .infinity
    }

    private var needsScroll: Bool {
        activeContentHeight > maxVisibleContentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 4) {
                ForEach(enabledProviders) { provider in
                    ProviderTab(
                        provider: provider,
                        isSelected: activeProvider == provider,
                        indicator: store.summaries[provider]?.status.indicator
                    ) {
                        selectedProvider = provider
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Selected provider content
            if needsScroll {
                ScrollView {
                    measuredContent
                }
                .frame(height: maxVisibleContentHeight)
            } else {
                measuredContent
            }

            Divider()

            // Error message
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            // Footer
            HStack {
                if let date = store.lastRefreshed {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = Int(context.date.timeIntervalSince(date))
                        Text("Updated \(seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min") ago")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 12) {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button {
                            Task { await store.refreshNow() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh")
                    }

                    Button {
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                    }
                    .help("Quit")
                }
                .buttonStyle(FooterIconButtonStyle())
                .font(.system(size: 13))
            }
            .padding(10)
        }
        .frame(width: MenuContentSizing.width)
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
                                .onAppear { tooltipHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, h in tooltipHeight = h }
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
                    Color.clear.onAppear {
                        if let provider = activeProvider {
                            contentHeights[provider] = proxy.size.height
                        }
                    }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        if let provider = activeProvider {
                            contentHeights[provider] = newHeight
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var selectedProviderContent: some View {
        if let provider = activeProvider, let summary = store.summaries[provider] {
            ProviderSectionView(
                provider: provider,
                summary: summary,
                store: store
            )
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - Provider Tab

struct ProviderTab: View {
    let provider: ProviderConfig
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
                Text(provider.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : isHovered ? Color.primary.opacity(0.05) : .clear)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Footer Icon Button Style

struct FooterIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? .primary : .secondary)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
