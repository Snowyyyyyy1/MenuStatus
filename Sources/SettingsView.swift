import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var store: StatusStore?
    @ObservedObject var updaterService: UpdaterService

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
            }

            Section("Providers") {
                ForEach(settings.providerConfigs.allProviders) { provider in
                    HStack {
                        Toggle(provider.displayName, isOn: Binding(
                            get: { settings.isEnabled(provider) },
                            set: { _ in settings.toggleProvider(provider) }
                        ))

                        if !provider.isBuiltIn {
                            Spacer()
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

                AddProviderRow(providerConfigs: settings.providerConfigs, store: store)
            }

            Section("Data") {
                HStack {
                    ExportButton(providerConfigs: settings.providerConfigs)
                    ImportButton(providerConfigs: settings.providerConfigs)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updaterService.automaticallyChecksForUpdates },
                    set: { updaterService.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates...") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.canCheckForUpdates)
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
                }
            }
    }
}

struct ProviderExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

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
