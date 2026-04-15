import SwiftUI
import UniformTypeIdentifiers

private struct LeadingTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.alignment = .left
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: LeadingTextField
        init(_ parent: LeadingTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var store: StatusStore?
    var updaterService: UpdaterService

    private var orderedProviders: [ProviderConfig] {
        settings.providerConfigs.orderedProviders(settings: settings)
    }

    private let intervalOptions: [(String, TimeInterval)] = [
        ("30 seconds", 30),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("10 minutes", 600),
    ]

    var body: some View {
        Form {
            Section("General") {
                Picker("Refresh interval", selection: $settings.refreshInterval) {
                    ForEach(intervalOptions, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }

                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                Picker("Menu bar icon", selection: $settings.iconStyle) {
                    Label("Outline", systemImage: "checkmark.circle")
                        .tag(MenuBarIconStyle.outline)
                    Label("Filled", systemImage: "checkmark.circle.fill")
                        .tag(MenuBarIconStyle.filled)
                    Label("Tinted", systemImage: "checkmark.circle.fill")
                        .tag(MenuBarIconStyle.tinted)
                }
            }

            Section("Providers") {
                List {
                    ForEach(orderedProviders) { (provider: ProviderConfig) in
                        ProviderRow(provider: provider, settings: settings)
                    }
                    .onMove { source, destination in
                        var ids = orderedProviders.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        settings.providerOrder = ids
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)

                AddProviderRow(providerConfigs: settings.providerConfigs, store: store)

                Button("Reset built-in providers") {
                    settings.providerConfigs.resetBuiltInProviders(settings: settings)
                }
                .help("Restore any built-in providers you have deleted")
                .disabled(settings.removedBuiltInIDs.isEmpty)
            }

            Section("Data") {
                HStack {
                    ExportButton(providerConfigs: settings.providerConfigs)
                    ImportButton(providerConfigs: settings.providerConfigs, store: store)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updaterService.automaticallyChecksForUpdates },
                    set: { updaterService.automaticallyChecksForUpdates = $0 }
                ))
                .disabled(!updaterService.isAvailable)

                Toggle("Download and install updates automatically", isOn: Binding(
                    get: { updaterService.automaticallyDownloadsUpdates },
                    set: { updaterService.automaticallyDownloadsUpdates = $0 }
                ))
                .disabled(!updaterService.isAvailable)

                Button("Check for Updates...") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.isAvailable || !updaterService.canCheckForUpdates)

                if !updaterService.isAvailable {
                    Text("In-app updates are only available in configured release builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize()
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let provider: ProviderConfig
    @Bindable var settings: SettingsStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(provider.displayName)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.isEnabled(provider) },
                        set: { _ in settings.toggleProvider(provider) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                HStack {
                    LeadingTextField(
                        text: Binding(
                            get: { settings.customProviderNames[provider.id] ?? "" },
                            set: { settings.customProviderNames[provider.id] = $0 }
                        ),
                        placeholder: "Alias"
                    )
                    .frame(maxWidth: 140)
                    .frame(height: 22)

                    Spacer()

                    if !provider.isBuiltIn {
                        Button {
                            settings.providerConfigs.removeProvider(id: provider.id, settings: settings)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

// MARK: - Add Provider

private struct AddProviderRow: View {
    let providerConfigs: ProviderConfigStore
    var store: StatusStore?
    @State private var urlText = ""
    @State private var isDetecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Status page URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await addProvider() }
                } label: {
                    if isDetecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .disabled(urlText.isEmpty || isDetecting)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func addProvider() async {
        errorMessage = nil
        var input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.hasPrefix("http") { input = "https://\(input)" }

        guard let url = URL(string: input) else {
            errorMessage = "Invalid URL"
            return
        }

        isDetecting = true
        defer { isDetecting = false }

        do {
            let config = try await ProviderConfigStore.detect(url: url)
            providerConfigs.addProvider(config)
            urlText = ""
            if let store {
                Task { await store.refreshNow() }
            }
        } catch {
            errorMessage = "Could not detect status page. Make sure it uses Statuspage or incident.io."
        }
    }
}

// MARK: - Import / Export

private struct ExportButton: View {
    let providerConfigs: ProviderConfigStore
    @State private var showExport = false

    var body: some View {
        Button("Export") { showExport = true }
            .fileExporter(
                isPresented: $showExport,
                document: ProviderExportDocument(providerConfigs: providerConfigs),
                contentType: .json,
                defaultFilename: "menustatus-providers"
            ) { _ in }
    }
}

private struct ImportButton: View {
    let providerConfigs: ProviderConfigStore
    var store: StatusStore?
    @State private var showImport = false
    @State private var importResult: String?

    var body: some View {
        Button("Import") { showImport = true }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result,
                      let data = try? Data(contentsOf: url) else { return }
                Task {
                    let added = try await providerConfigs.importJSON(data)
                    importResult = "Added \(added.count) provider(s)"
                    if !added.isEmpty, let store {
                        await store.refreshNow()
                    }
                }
            }
    }
}

struct ProviderExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    @MainActor
    init(providerConfigs: ProviderConfigStore) {
        self.data = (try? providerConfigs.exportJSON()) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
