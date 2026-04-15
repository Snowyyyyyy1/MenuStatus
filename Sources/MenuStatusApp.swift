import AppKit
import SwiftUI

@main
struct MenuStatusApp: App {
    @NSApplicationDelegateAdaptor(MenuStatusAppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var store: StatusStore
    @State private var benchmarkStore: AIStupidLevelStore
    @State private var settingsWindowPresenter = SettingsWindowPresenter()
    @State private var updaterService = UpdaterService()

    init() {
        let settings = SettingsStore()
        let providerConfigs = ProviderConfigStore(removedBuiltInIDs: settings.removedBuiltInIDs)
        settings.attachProviderConfigs(providerConfigs)
        let store = StatusStore(settings: settings)
        store.startPolling()
        let benchmarkStore = AIStupidLevelStore()
        benchmarkStore.startPolling(interval: 300)
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _benchmarkStore = State(initialValue: benchmarkStore)
    }

    var body: some Scene {
        let _ = configureStatusItemHost()

        Settings {
            SettingsView(settings: settings, store: store, updaterService: updaterService)
        }
        .windowResizability(.contentSize)
    }

    @MainActor
    private func configureStatusItemHost() {
        appDelegate.configure(
            store: store,
            benchmarkStore: benchmarkStore,
            indicator: store.overallIndicator,
            iconStyle: settings.iconStyle,
            openSettings: {
                settingsWindowPresenter.show {
                    SettingsView(settings: settings, store: store, updaterService: updaterService)
                }
            }
        )
    }
}

enum MenuBarIconRenderer {
    private nonisolated(unsafe) static var cache: (indicator: StatusIndicator, style: MenuBarIconStyle, image: NSImage)?

    static func image(indicator: StatusIndicator, style: MenuBarIconStyle) -> NSImage {
        if let c = Self.cache, c.indicator == indicator, c.style == style {
            return c.image
        }
        let image = buildImage(indicator: indicator, style: style)
        Self.cache = (indicator, style, image)
        return image
    }

    private static func buildImage(indicator: StatusIndicator, style: MenuBarIconStyle) -> NSImage {
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        switch style {
        case .outline:
            return buildOutline(indicator: indicator, sizeConfig: sizeConfig)
        case .filled:
            return buildFilledCutout(indicator: indicator, sizeConfig: sizeConfig)
        case .tinted:
            return buildTinted(indicator: indicator, sizeConfig: sizeConfig)
        }
    }

    // Outline: template when operational, colored outline otherwise
    private static func buildOutline(indicator: StatusIndicator, sizeConfig: NSImage.SymbolConfiguration) -> NSImage {
        let symbol = indicator.menuBarSymbol
        if indicator == .none {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: indicator.displayName)?
                .withSymbolConfiguration(sizeConfig) ?? NSImage()
            image.isTemplate = true
            return image
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [NSColor(indicator.color)]).applying(sizeConfig)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: indicator.displayName)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }

    // Filled cutout: solid background shape with transparent foreground symbol
    private static func buildFilledCutout(indicator: StatusIndicator, sizeConfig: NSImage.SymbolConfiguration) -> NSImage {
        let symbol = indicator.sfSymbol
        let baseColor = NSColor(indicator.color)

        // Solid colored symbol (both layers same color)
        let solidConfig = NSImage.SymbolConfiguration(paletteColors: [baseColor, baseColor]).applying(sizeConfig)
        let solidImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(solidConfig) ?? NSImage()

        // Foreground-only mask
        let maskConfig = NSImage.SymbolConfiguration(paletteColors: [.white, .clear]).applying(sizeConfig)
        let maskImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(maskConfig) ?? NSImage()

        // Punch out the foreground shape
        let result = NSImage(size: solidImage.size, flipped: false) { rect in
            solidImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            maskImage.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1.0)
            return true
        }
        result.isTemplate = false
        return result
    }

    // Tinted: colored foreground symbol on dim colored background
    private static func buildTinted(indicator: StatusIndicator, sizeConfig: NSImage.SymbolConfiguration) -> NSImage {
        let symbol = indicator.sfSymbol
        let baseColor = NSColor(indicator.color)
        let config = NSImage.SymbolConfiguration(hierarchicalColor: baseColor).applying(sizeConfig)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: indicator.displayName)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }
}
