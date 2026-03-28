import AppKit
import SwiftUI

@main
struct MenuStatusApp: App {
    @State private var settings: SettingsStore
    @State private var store: StatusStore
    @StateObject private var updaterService = UpdaterService()

    init() {
        let providerConfigs = ProviderConfigStore()
        let settings = SettingsStore(providerConfigs: providerConfigs)
        let store = StatusStore(settings: settings)
        store.startPolling()
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuContentView(store: store)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(settings: settings, store: store, updaterService: updaterService)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var menuBarIcon: NSImage {
        let indicator = store.overallIndicator
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let symbol = indicator.menuBarSymbol

        if indicator == .none {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: indicator.displayName)?
                .withSymbolConfiguration(sizeConfig) ?? NSImage()
            image.isTemplate = true
            return image
        }

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor(indicator.color)])
        let config = colorConfig.applying(sizeConfig)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: indicator.displayName)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }
}
