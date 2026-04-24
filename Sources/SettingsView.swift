import AppKit
import Observation
import SwiftUI

enum SettingsPane: CaseIterable, Identifiable {
    case general
    case providers
    case updates
    case about

    static let defaultWidth: CGFloat = 496
    static let providersWidth: CGFloat = 720
    static let windowHeight: CGFloat = 580

    var id: Self { self }

    var iconName: String {
        switch self {
        case .general:
            return "gearshape"
        case .providers:
            return "server.rack"
        case .updates:
            return "arrow.triangle.2.circlepath"
        case .about:
            return "info.circle"
        }
    }

    var preferredWidth: CGFloat {
        self == .providers ? Self.providersWidth : Self.defaultWidth
    }

    var preferredHeight: CGFloat {
        Self.windowHeight
    }

    static func windowTitleMatch(_ title: String, locale: Locale) -> Self? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackLocales = [
            locale,
            Locale(identifier: "en"),
            Locale(identifier: "zh-Hans"),
        ]

        return allCases.first { pane in
            fallbackLocales.contains { candidateLocale in
                SettingsCopy.paneTitle(pane, locale: candidateLocale) == normalizedTitle
            }
        }
    }
}

enum SettingsProviderSelection {
    static func resolvedSelection(current: String?, providers: [ProviderConfig]) -> String? {
        guard let firstProvider = providers.first else { return nil }
        guard let current, providers.contains(where: { $0.id == current }) else {
            return firstProvider.id
        }
        return current
    }
}

@MainActor
@Observable
final class SettingsPaneSelection {
    var pane: SettingsPane = .general
}

enum ProviderUtilitySectionState {
    static func showsResetBuiltInsButton(removedBuiltInIDs: Set<String>) -> Bool {
        !removedBuiltInIDs.isEmpty
    }
}

enum ProviderUtilitySectionPlacement: Equatable {
    case sidebarFooter

    static let `default`: Self = .sidebarFooter
}

enum ProviderSettingsMetrics {
    static let reorderHandleSize: CGFloat = 12
    static let reorderDotSize: CGFloat = 2
    static let reorderDotSpacing: CGFloat = 3
    static let sidebarWidth: CGFloat = 240
    static let sidebarCornerRadius: CGFloat = 12
    static let detailMaxWidth: CGFloat = 640
    static let sidebarSubtitleHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let layout = NSLayoutManager()
        return ceil(layout.defaultLineHeight(for: font) * 2)
    }()
}

@MainActor
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var store: StatusStore?
    var updaterService: UpdaterService
    @Bindable var paneSelection: SettingsPaneSelection

    @Environment(\.locale) private var locale
    @State private var contentWidth: CGFloat = SettingsPane.general.preferredWidth
    @State private var contentHeight: CGFloat = SettingsPane.general.preferredHeight
    @State private var hostWindow: NSWindow?

    private let intervalOptions: [TimeInterval] = [30, 60, 120, 300, 600]

    var body: some View {
        TabView(selection: $paneSelection.pane) {
            GeneralSettingsPane(settings: settings, intervalOptions: intervalOptions)
                .tabItem {
                    Label(SettingsCopy.paneTitle(.general, locale: locale), systemImage: SettingsPane.general.iconName)
                }
                .tag(SettingsPane.general)

            ProviderSettingsPane(settings: settings, store: store)
                .tabItem {
                    Label(SettingsCopy.paneTitle(.providers, locale: locale), systemImage: SettingsPane.providers.iconName)
                }
                .tag(SettingsPane.providers)

            UpdateSettingsPane(settings: settings, updaterService: updaterService)
                .tabItem {
                    Label(SettingsCopy.paneTitle(.updates, locale: locale), systemImage: SettingsPane.updates.iconName)
                }
                .tag(SettingsPane.updates)

            AboutSettingsPane()
                .tabItem {
                    Label(SettingsCopy.paneTitle(.about, locale: locale), systemImage: SettingsPane.about.iconName)
                }
                .tag(SettingsPane.about)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: contentWidth, height: contentHeight)
        .background(
            SettingsWindowAccessor { window in
                guard hostWindow !== window else { return }
                hostWindow = window
                applyWindowSize(for: paneSelection.pane, animate: false)
            }
        )
        .onAppear {
            updateLayout(for: paneSelection.pane, animate: false)
        }
        .onChange(of: paneSelection.pane) { _, newValue in
            updateLayout(for: newValue, animate: true)
        }
    }

    private func updateLayout(for pane: SettingsPane, animate: Bool) {
        let change = {
            contentWidth = pane.preferredWidth
            contentHeight = pane.preferredHeight
        }
        if animate {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                change()
            }
        } else {
            change()
        }
        applyWindowSize(for: pane, animate: animate)
    }

    private func applyWindowSize(for pane: SettingsPane, animate: Bool) {
        guard let hostWindow else { return }

        let targetContentSize = SettingsWindowContentSizing.targetContentSize(for: pane)
        let currentContentSize = hostWindow.contentRect(forFrameRect: hostWindow.frame).size
        guard SettingsWindowContentSizing.needsResize(
            currentContentSize: currentContentSize,
            targetContentSize: targetContentSize
        ) else {
            return
        }

        hostWindow.setContentSize(targetContentSize)
    }
}

enum SettingsWindowContentSizing {
    static func targetContentSize(for pane: SettingsPane) -> NSSize {
        NSSize(width: pane.preferredWidth, height: pane.preferredHeight)
    }

    static func needsResize(currentContentSize: NSSize, targetContentSize: NSSize) -> Bool {
        abs(currentContentSize.width - targetContentSize.width) > 0.5 ||
            abs(currentContentSize.height - targetContentSize.height) > 0.5
    }

}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

private struct GeneralSettingsPane: View {
    @Bindable var settings: SettingsStore
    let intervalOptions: [TimeInterval]

    @Environment(\.locale) private var locale

    var body: some View {
        SettingsScrollPane {
            SettingsSection(contentSpacing: 12) {
                SettingsSectionLabel(title: SettingsCopy.literal(locale: locale, english: "System", chinese: "系统"))

                PreferenceToggleRow(
                    title: AppStrings.localizedString(
                        "settings.launch-at-login",
                        locale: locale,
                        defaultValue: "Launch at login"
                    ),
                    subtitle: AppStrings.localizedString(
                        "settings.helper.launch-at-login",
                        locale: locale,
                        defaultValue: "Start automatically when macOS signs you in."
                    ),
                    binding: $settings.launchAtLogin
                )
            }

            Divider()

            SettingsSection(contentSpacing: 12) {
                SettingsSectionLabel(title: SettingsCopy.literal(locale: locale, english: "Behavior", chinese: "行为"))

                PreferenceControlRow(
                    title: AppStrings.localizedString(
                        "settings.refresh.label",
                        locale: locale,
                        defaultValue: "Refresh interval"
                    ),
                    subtitle: AppStrings.localizedString(
                        "settings.helper.refresh",
                        locale: locale,
                        defaultValue: "How often MenuStatus refreshes all enabled providers."
                    )
                ) {
                    Picker(
                        AppStrings.localizedString(
                            "settings.refresh.label",
                            locale: locale,
                            defaultValue: "Refresh interval"
                        ),
                        selection: $settings.refreshInterval
                    ) {
                        ForEach(intervalOptions, id: \.self) { value in
                            Text(AppStrings.refreshIntervalLabel(value, locale: locale)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .controlSize(.small)
                    .focusable(false)
                }

                PreferenceControlRow(
                    title: AppStrings.localizedString(
                        "settings.language.label",
                        locale: locale,
                        defaultValue: "Language"
                    ),
                    subtitle: AppStrings.localizedString(
                        "settings.helper.language",
                        locale: locale,
                        defaultValue: "Choose app language without changing system locale."
                    )
                ) {
                    Picker(
                        AppStrings.localizedString(
                            "settings.language.label",
                            locale: locale,
                            defaultValue: "Language"
                        ),
                        selection: $settings.languagePreference
                    ) {
                        ForEach(AppLanguagePreference.allCases) { preference in
                            Text(AppStrings.languagePreferenceName(preference, locale: locale))
                                .tag(preference)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .controlSize(.small)
                    .focusable(false)
                }
            }

            Divider()

            SettingsSection(contentSpacing: 12) {
                SettingsSectionLabel(title: SettingsCopy.literal(locale: locale, english: "Menu Bar", chinese: "菜单栏"))

                PreferenceControlRow(
                    title: AppStrings.localizedString(
                        "settings.icon.label",
                        locale: locale,
                        defaultValue: "Menu bar icon"
                    ),
                    subtitle: AppStrings.localizedString(
                        "settings.helper.icon",
                        locale: locale,
                        defaultValue: "Pick the menu bar treatment that reads best at a glance."
                    )
                ) {
                    Picker(
                        AppStrings.localizedString(
                            "settings.icon.label",
                            locale: locale,
                            defaultValue: "Menu bar icon"
                        ),
                        selection: $settings.iconStyle
                    ) {
                        Text(AppStrings.menuBarIconStyleName(.outline, locale: locale))
                            .tag(MenuBarIconStyle.outline)
                        Text(AppStrings.menuBarIconStyleName(.filled, locale: locale))
                            .tag(MenuBarIconStyle.filled)
                        Text(AppStrings.menuBarIconStyleName(.tinted, locale: locale))
                            .tag(MenuBarIconStyle.tinted)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .controlSize(.small)
                    .focusable(false)
                }
            }
        }
    }
}

private struct ProviderSettingsPane: View {
    @Bindable var settings: SettingsStore
    var store: StatusStore?

    @State private var selectedProviderID: String?

    private var orderedProviders: [ProviderConfig] {
        settings.providerConfigs.orderedProviders(settings: settings)
    }

    private var selectedProvider: ProviderConfig? {
        guard let selectedProviderID else { return nil }
        return orderedProviders.first(where: { $0.id == selectedProviderID })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ProviderSidebarList(
                settings: settings,
                providers: orderedProviders,
                store: store,
                selection: $selectedProviderID,
                onProviderAdded: { selectedProviderID = $0 }
            )

            if let provider = selectedProvider ?? orderedProviders.first {
                ProviderDetailView(
                    settings: settings,
                    provider: provider
                )
            } else {
                Text("No providers")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: syncSelection)
        .onChange(of: orderedProviders.map(\.id)) { _, _ in
            syncSelection()
        }
    }

    private func syncSelection() {
        selectedProviderID = SettingsProviderSelection.resolvedSelection(
            current: selectedProviderID,
            providers: orderedProviders
        )
    }
}

private struct UpdateSettingsPane: View {
    @Bindable var settings: SettingsStore
    var updaterService: UpdaterService

    @Environment(\.locale) private var locale

    var body: some View {
        SettingsScrollPane {
            SettingsSection(contentSpacing: 12) {
                SettingsSectionLabel(title: SettingsCopy.literal(locale: locale, english: "Updates", chinese: "更新"))

                PreferenceToggleRow(
                    title: AppStrings.localizedString(
                        "settings.updates.check-automatically",
                        locale: locale,
                        defaultValue: "Check for updates automatically"
                    ),
                    subtitle: AppStrings.localizedString(
                        "settings.helper.updates",
                        locale: locale,
                        defaultValue: "Sparkle can check automatically or let you trigger checks manually."
                    ),
                    binding: Binding(
                        get: { updaterService.automaticallyChecksForUpdates },
                        set: { updaterService.automaticallyChecksForUpdates = $0 }
                    )
                )
                .disabled(!updaterService.isAvailable)

                PreferenceToggleRow(
                    title: AppStrings.localizedString(
                        "settings.updates.download-automatically",
                        locale: locale,
                        defaultValue: "Download and install updates automatically"
                    ),
                    subtitle: SettingsCopy.literal(
                        locale: locale,
                        english: "Automatically install new releases when Sparkle can apply them safely.",
                        chinese: "当 Sparkle 可安全应用更新时，自动下载并安装新版本。"
                    ),
                    binding: Binding(
                        get: { updaterService.automaticallyDownloadsUpdates },
                        set: { updaterService.automaticallyDownloadsUpdates = $0 }
                    )
                )
                .disabled(!updaterService.isAvailable)

                PreferenceToggleRow(
                    title: AppStrings.localizedString(
                        "settings.updates.beta",
                        locale: locale,
                        defaultValue: "Receive beta updates"
                    ),
                    subtitle: AppStrings.localizedString(
                        "settings.helper.updates.beta",
                        locale: locale,
                        defaultValue: "Opt into pre-release builds tagged as beta or rc."
                    ),
                    binding: $settings.allowsBetaUpdates
                )
                .disabled(!updaterService.isAvailable)
                .onChange(of: settings.allowsBetaUpdates) { _, _ in
                    updaterService.checkForUpdatesInBackground()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button(
                        AppStrings.localizedString(
                            "settings.updates.check-now",
                            locale: locale,
                            defaultValue: "Check for Updates..."
                        )
                    ) {
                        updaterService.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!updaterService.isAvailable || !updaterService.canCheckForUpdates)
                    .focusable(false)

                    if let diagnosticMessage = updaterService.diagnosticMessage {
                        Text(diagnosticMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct AboutSettingsPane: View {
    @Environment(\.locale) private var locale
    @State private var iconHover = false

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MenuStatus"
    }

    private var versionLine: String {
        let label = AppStrings.localizedString(
            "settings.about.version",
            locale: locale,
            defaultValue: "Version"
        )
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return label
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "\(label) \(version) (\(build))"
        }
        return "\(label) \(version)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                open(.github)
            } label: {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(iconHover ? 1.05 : 1)
                    .shadow(color: iconHover ? .accentColor.opacity(0.18) : .clear, radius: 6)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { hovering in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    iconHover = hovering
                }
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title3.weight(.semibold))
                Text(versionLine)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(
                    SettingsCopy.literal(
                        locale: locale,
                        english: "Open-source status monitor for incident.io and Statuspage services.",
                        chinese: "面向 incident.io 与 Statuspage 服务的开源状态栏监控工具。"
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .center, spacing: 10) {
                ForEach(AboutLinkDestination.allCases, id: \.self) { destination in
                    AboutLinkRow(
                        icon: destination.iconName,
                        title: destination.title(locale: locale)
                    ) {
                        open(destination)
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Text("AGPL-3.0")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func open(_ destination: AboutLinkDestination) {
        guard let url = URL(string: destination.urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum AboutLinkDestination: CaseIterable {
    case github
    case reportIssue
    case releases

    var iconName: String {
        switch self {
        case .github:
            return "chevron.left.slash.chevron.right"
        case .reportIssue:
            return "exclamationmark.bubble"
        case .releases:
            return "shippingbox"
        }
    }

    var urlString: String {
        switch self {
        case .github:
            return "https://github.com/Snowyyyyyy1/MenuStatus"
        case .reportIssue:
            return "https://github.com/Snowyyyyyy1/MenuStatus/issues/new/choose"
        case .releases:
            return "https://github.com/Snowyyyyyy1/MenuStatus/releases"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .github:
            return "GitHub"
        case .reportIssue:
            return SettingsCopy.literal(
                locale: locale,
                english: "Report Issue",
                chinese: "问题反馈"
            )
        case .releases:
            return SettingsCopy.literal(
                locale: locale,
                english: "Releases",
                chinese: "版本发布"
            )
        }
    }
}

private struct AboutLinkRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .underline(hovering, color: .accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct ProviderSidebarList: View {
    @Bindable var settings: SettingsStore
    let providers: [ProviderConfig]
    var store: StatusStore?
    @Binding var selection: String?
    let onProviderAdded: (String) -> Void

    @Environment(\.locale) private var locale

    private var showsResetBuiltInsButton: Bool {
        ProviderUtilitySectionState.showsResetBuiltInsButton(
            removedBuiltInIDs: settings.removedBuiltInIDs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(providers) { provider in
                    ProviderSidebarRow(provider: provider, settings: settings)
                        .tag(provider.id)
                }
                .onMove { source, destination in
                    var ids = providers.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    settings.providerOrder = ids
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .focusable(false)

            Divider()

            SettingsSection(
                title: SettingsCopy.literal(locale: locale, english: "Add Provider", chinese: "添加服务源"),
                caption: AppStrings.localizedString(
                    "settings.helper.discovery",
                    locale: locale,
                    defaultValue: "Supports Atlassian Statuspage and incident.io URLs."
                ),
                contentSpacing: 10
            ) {
                AddProviderRow(
                    providerConfigs: settings.providerConfigs,
                    store: store,
                    showsResetBuiltInsButton: showsResetBuiltInsButton,
                    onResetBuiltIns: {
                        settings.providerConfigs.resetBuiltInProviders(settings: settings)
                    }
                ) { addedProvider in
                    onProviderAdded(addedProvider.id)
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: ProviderSettingsMetrics.sidebarCornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ProviderSettingsMetrics.sidebarCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ProviderSettingsMetrics.sidebarCornerRadius, style: .continuous))
        .frame(
            minWidth: ProviderSettingsMetrics.sidebarWidth,
            maxWidth: ProviderSettingsMetrics.sidebarWidth,
            maxHeight: .infinity
        )
    }
}

private struct ProviderSidebarRow: View {
    let provider: ProviderConfig
    @Bindable var settings: SettingsStore

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsReorderHandle()
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .help(SettingsCopy.literal(locale: locale, english: "Drag to reorder", chinese: "拖拽调整顺序"))

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayName(for: provider))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(height: ProviderSettingsMetrics.sidebarSubtitleHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            Toggle("", isOn: settings.enabledBinding(for: provider))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .focusable(false)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let firstLine = provider.settingsHostDisplay
        let secondLine = "\(SettingsCopy.providerPlatformName(provider.platform, locale: locale)) • \(SettingsCopy.providerTypeName(isBuiltIn: provider.isBuiltIn, locale: locale))"
        return "\(firstLine)\n\(secondLine)"
    }

    private var statusText: String {
        guard settings.isEnabled(provider) else {
            let lines = subtitle.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                return "\(SettingsCopy.literal(locale: locale, english: "Disabled", chinese: "已停用")) — \(lines[0])\n\(lines[1])"
            }
            return "\(SettingsCopy.literal(locale: locale, english: "Disabled", chinese: "已停用")) — \(subtitle)"
        }
        return subtitle
    }
}

private struct ProviderDetailView: View {
    @Bindable var settings: SettingsStore
    let provider: ProviderConfig

    @Environment(\.locale) private var locale

    private var infoRows: [(String, String)] {
        [
            (SettingsCopy.literal(locale: locale, english: "URL", chinese: "URL"), provider.baseURL.absoluteString),
            (SettingsCopy.literal(locale: locale, english: "Host", chinese: "主机"), provider.settingsHostDisplay),
            (SettingsCopy.literal(locale: locale, english: "Platform", chinese: "平台"), SettingsCopy.providerPlatformName(provider.platform, locale: locale)),
            (SettingsCopy.literal(locale: locale, english: "Type", chinese: "类型"), SettingsCopy.providerTypeName(isBuiltIn: provider.isBuiltIn, locale: locale)),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProviderDetailHeader(provider: provider, settings: settings)

                SettingsSection(title: SettingsCopy.literal(locale: locale, english: "Source", chinese: "来源")) {
                    ProviderInfoGrid(rows: infoRows)
                }

                SettingsSection(title: SettingsCopy.literal(locale: locale, english: "Settings", chinese: "设置")) {
                    PreferenceControlRow(
                        title: SettingsCopy.literal(locale: locale, english: "Alias", chinese: "别名"),
                        subtitle: SettingsCopy.literal(
                            locale: locale,
                            english: "Shown in the menu and provider list.",
                            chinese: "显示在菜单和服务源列表中。"
                        )
                    ) {
                        TextField(
                            AppStrings.localizedString(
                                "settings.providers.alias.placeholder",
                                locale: locale,
                                defaultValue: "Alias"
                            ),
                            text: Binding(
                                get: { settings.customProviderNames[provider.id] ?? "" },
                                set: { settings.customProviderNames[provider.id] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.footnote)
                        .frame(width: 190, height: 22)
                    }
                }

                if !provider.isBuiltIn {
                    SettingsSection(title: SettingsCopy.literal(locale: locale, english: "Actions", chinese: "操作")) {
                        Button(role: .destructive) {
                            settings.providerConfigs.removeProvider(id: provider.id, settings: settings)
                        } label: {
                            Text(SettingsCopy.literal(locale: locale, english: "Delete provider", chinese: "删除服务源"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .focusable(false)
                    }
                }
            }
            .frame(maxWidth: ProviderSettingsMetrics.detailMaxWidth, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProviderDetailHeader: View {
    let provider: ProviderConfig
    @Bindable var settings: SettingsStore

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.displayName(for: provider))
                    .font(.title3.weight(.semibold))

                Text(detailSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: settings.enabledBinding(for: provider))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .focusable(false)
        }
    }

    private var detailSubtitle: String {
        "\(provider.settingsHostDisplay) • \(SettingsCopy.providerPlatformName(provider.platform, locale: locale)) • \(SettingsCopy.providerTypeName(isBuiltIn: provider.isBuiltIn, locale: locale))"
    }
}

private struct ProviderInfoGrid: View {
    let rows: [(String, String)]

    private var labelWidth: CGFloat {
        rows.map { SettingsCopy.labelWidth(for: $0.0) }.max() ?? 0
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow(alignment: .top) {
                    Text(row.0)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)

                    Text(verbatim: row.1)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.footnote)
    }
}

private struct AddProviderRow: View {
    let providerConfigs: ProviderConfigStore
    var store: StatusStore?
    let showsResetBuiltInsButton: Bool
    let onResetBuiltIns: () -> Void
    let onProviderAdded: (ProviderConfig) -> Void

    @State private var urlText = ""
    @State private var isDetecting = false
    @State private var errorMessage: String?
    @Environment(\.locale) private var locale

    private var canSubmit: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDetecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                AppStrings.localizedString(
                    "settings.providers.url.placeholder",
                    locale: locale,
                    defaultValue: "Status page URL"
                ),
                text: $urlText
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                guard canSubmit else { return }
                Task { await addProvider() }
            }

            HStack(alignment: .center, spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    Task { await addProvider() }
                } label: {
                    if isDetecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(
                            AppStrings.localizedString(
                                "settings.providers.add",
                                locale: locale,
                                defaultValue: "Add"
                            )
                        )
                    }
                }
                .frame(minWidth: 60)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canSubmit)
                .focusable(false)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsResetBuiltInsButton {
                Button(
                    AppStrings.localizedString(
                        "settings.providers.reset",
                        locale: locale,
                        defaultValue: "Reset built-in providers"
                    )
                ) {
                    onResetBuiltIns()
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .focusable(false)
                .help(
                    AppStrings.localizedString(
                        "settings.providers.reset.help",
                        locale: locale,
                        defaultValue: "Restore any built-in providers you have deleted"
                    )
                )
            }
        }
    }

    private func addProvider() async {
        errorMessage = nil

        var input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.hasPrefix("http") {
            input = "https://\(input)"
        }

        guard let url = URL(string: input) else {
            errorMessage = AppStrings.localizedString(
                "settings.providers.invalid-url",
                locale: locale,
                defaultValue: "Invalid URL"
            )
            return
        }

        isDetecting = true
        defer { isDetecting = false }

        do {
            let config = try await ProviderConfigStore.detect(url: url)
            providerConfigs.addProvider(config)
            onProviderAdded(config)
            urlText = ""
            if let store {
                Task { await store.refreshNow() }
            }
        } catch {
            errorMessage = AppStrings.localizedString(
                "settings.providers.detect-failure",
                locale: locale,
                defaultValue: "Could not detect status page. Make sure it uses Statuspage or incident.io."
            )
        }
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var binding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5.4) {
            Toggle(isOn: $binding) {
                Text(title)
                    .font(.body)
            }
            .toggleStyle(.checkbox)
            .focusable(false)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String?
    let caption: String?
    let contentSpacing: CGFloat
    private let content: Content

    init(
        title: String? = nil,
        caption: String? = nil,
        contentSpacing: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.caption = caption
        self.contentSpacing = contentSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: contentSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct PreferenceControlRow<Control: View>: View {
    let title: String
    let subtitle: String?
    private let control: Control

    init(title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control
        }
    }
}

private struct SettingsScrollPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsReorderHandle: View {
    var body: some View {
        VStack(spacing: ProviderSettingsMetrics.reorderDotSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: ProviderSettingsMetrics.reorderDotSpacing) {
                    Circle()
                        .frame(
                            width: ProviderSettingsMetrics.reorderDotSize,
                            height: ProviderSettingsMetrics.reorderDotSize
                        )
                    Circle()
                        .frame(
                            width: ProviderSettingsMetrics.reorderDotSize,
                            height: ProviderSettingsMetrics.reorderDotSize
                        )
                }
            }
        }
        .foregroundStyle(.tertiary)
        .frame(
            width: ProviderSettingsMetrics.reorderHandleSize,
            height: ProviderSettingsMetrics.reorderHandleSize
        )
        .accessibilityHidden(true)
    }
}

private enum SettingsCopy {
    static func paneTitle(_ pane: SettingsPane, locale: Locale) -> String {
        switch pane {
        case .general:
            return AppStrings.localizedString("settings.general", locale: locale, defaultValue: "General")
        case .providers:
            return AppStrings.localizedString("settings.providers", locale: locale, defaultValue: "Providers")
        case .updates:
            return AppStrings.localizedString("settings.updates", locale: locale, defaultValue: "Updates")
        case .about:
            return AppStrings.localizedString("settings.about", locale: locale, defaultValue: "About")
        }
    }

    static func providerPlatformName(_ platform: StatusPlatform, locale: Locale) -> String {
        switch platform {
        case .atlassianStatuspage:
            return literal(locale: locale, english: "Statuspage", chinese: "Statuspage")
        case .incidentIO:
            return "incident.io"
        }
    }

    static func providerTypeName(isBuiltIn: Bool, locale: Locale) -> String {
        if isBuiltIn {
            return literal(locale: locale, english: "Built-in", chinese: "内置")
        }
        return literal(locale: locale, english: "Custom", chinese: "自定义")
    }

    static func labelWidth(for text: String) -> CGFloat {
        let nsText = text as NSString
        let size = nsText.size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        return ceil(size.width)
    }

    static func literal(locale: Locale, english: String, chinese: String) -> String {
        isChinese(locale) ? chinese : english
    }

    private static func isChinese(_ locale: Locale) -> Bool {
        locale.identifier.hasPrefix("zh") || locale.language.languageCode?.identifier == "zh"
    }
}

private extension ProviderConfig {
    var settingsHostDisplay: String {
        baseURL.host ?? baseURL.absoluteString
    }
}

private extension SettingsStore {
    func enabledBinding(for provider: ProviderConfig) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(provider) },
            set: { newValue in
                if newValue != self.isEnabled(provider) {
                    self.toggleProvider(provider)
                }
            }
        )
    }
}
