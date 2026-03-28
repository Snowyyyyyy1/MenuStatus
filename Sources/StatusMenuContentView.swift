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
    @State private var contentHeight: CGFloat = 0

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

    private var needsScroll: Bool {
        contentHeight > maxVisibleContentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(enabledProviders) { provider in
                    ProviderTab(
                        provider: provider,
                        isSelected: activeProvider == provider,
                        indicator: store.summaries[provider]?.status.indicator
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedProvider = provider
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
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
                    Text("Updated \(date, style: .relative) ago")
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
                .buttonStyle(.borderless)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: MenuContentSizing.width)
    }

    private var measuredContent: some View {
        selectedProviderContent
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        contentHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        contentHeight = newHeight
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    if let indicator {
                        Circle()
                            .fill(indicator.color)
                            .frame(width: 6, height: 6)
                    }
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                }
                .foregroundStyle(isSelected ? .primary : .secondary)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
