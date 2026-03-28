import SwiftUI

struct StatusMenuContentView: View {
    let store: StatusStore
    @State private var selectedProvider: Provider = .openAI

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    ProviderTab(
                        provider: provider,
                        isSelected: selectedProvider == provider,
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
            ScrollView {
                if let summary = store.summaries[selectedProvider] {
                    ProviderSectionView(
                        provider: selectedProvider,
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
            .frame(minHeight: 400, maxHeight: .infinity)

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
                if store.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button("Refresh") {
                    Task { await store.refreshNow() }
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .task {
            store.startPolling()
        }
    }
}

// MARK: - Provider Tab

struct ProviderTab: View {
    let provider: Provider
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
