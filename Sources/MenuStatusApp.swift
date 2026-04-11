import AppKit
import MenuBarExtraAccess
import SwiftUI

@main
struct MenuStatusApp: App {
    @State private var settings: SettingsStore
    @State private var store: StatusStore
    @State private var benchmarkStore: AIStupidLevelStore
    @State private var isMenuPresented: Bool = false
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
        MenuBarExtra {
            StatusMenuContentView(store: store)
                .introspectMenuBarExtraWindow { window in
                    window.animationBehavior = .utilityWindow
                }
        } label: {
            MenuBarIcon(indicator: store.overallIndicator, style: settings.iconStyle)
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented)
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(settings: settings, store: store, updaterService: updaterService)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

private struct MenuBarIcon: View {
    let indicator: StatusIndicator
    let style: MenuBarIconStyle

    private nonisolated(unsafe) static var cache: (indicator: StatusIndicator, style: MenuBarIconStyle, image: NSImage)?

    var body: some View {
        Image(nsImage: cachedImage())
    }

    private func cachedImage() -> NSImage {
        if let c = Self.cache, c.indicator == indicator, c.style == style {
            return c.image
        }
        let image = buildImage()
        Self.cache = (indicator, style, image)
        return image
    }

    private func buildImage() -> NSImage {
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        switch style {
        case .outline:
            return buildOutline(sizeConfig: sizeConfig)
        case .filled:
            return buildFilledCutout(sizeConfig: sizeConfig)
        case .tinted:
            return buildTinted(sizeConfig: sizeConfig)
        }
    }

    // Outline: template when operational, colored outline otherwise
    private func buildOutline(sizeConfig: NSImage.SymbolConfiguration) -> NSImage {
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
    private func buildFilledCutout(sizeConfig: NSImage.SymbolConfiguration) -> NSImage {
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
    private func buildTinted(sizeConfig: NSImage.SymbolConfiguration) -> NSImage {
        let symbol = indicator.sfSymbol
        let baseColor = NSColor(indicator.color)
        let config = NSImage.SymbolConfiguration(hierarchicalColor: baseColor).applying(sizeConfig)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: indicator.displayName)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }
}
