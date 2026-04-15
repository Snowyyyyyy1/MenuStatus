import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {
    private var windowController: NSWindowController?

    @discardableResult
    func show<Content: View>(@ViewBuilder content: () -> Content) -> NSWindow? {
        let controller = resolvedWindowController(rootView: AnyView(content()))
        controller.showWindow(nil)
        guard let window = controller.window else { return nil }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private func resolvedWindowController(rootView: AnyView) -> NSWindowController {
        if let windowController {
            update(windowController: windowController, rootView: rootView)
            return windowController
        }

        let windowController = buildWindowController(rootView: rootView)
        self.windowController = windowController
        return windowController
    }

    private func update(windowController: NSWindowController, rootView: AnyView) {
        guard let hostingController = windowController.contentViewController as? NSHostingController<AnyView> else {
            return
        }
        hostingController.rootView = rootView
        applyPreferredContentSize(using: hostingController, to: windowController.window)
    }

    private func buildWindowController(rootView: AnyView) -> NSWindowController {
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MenuStatusSettings")
        window.contentViewController = hostingController

        applyPreferredContentSize(using: hostingController, to: window)
        window.center()
        return NSWindowController(window: window)
    }

    private func applyPreferredContentSize(using hostingController: NSHostingController<AnyView>, to window: NSWindow?) {
        hostingController.view.layoutSubtreeIfNeeded()
        let preferredSize = hostingController.preferredContentSize
        guard preferredSize.width > 0, preferredSize.height > 0 else { return }
        window?.setContentSize(preferredSize)
    }
}
