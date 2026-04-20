import AppKit
import SwiftUI

enum SettingsSceneBridge {
    static let openNotification = Notification.Name("MenuStatusOpenSettings")
    static let keepaliveWindowTitle = "MenuStatusLifecycleKeepalive"
    static let keepaliveSceneSize = CGSize(width: 20, height: 20)
    private static let hiddenWindowOrigin = NSPoint(x: -5000, y: -5000)
    private static let hiddenWindowSize = NSSize(width: 1, height: 1)

    @MainActor
    static func requestOpen() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: openNotification, object: nil)
    }

    @MainActor
    static func configureKeepaliveWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { $0.title == keepaliveWindowTitle }) else {
            return
        }

        window.styleMask = [.borderless]
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.isExcludedFromWindowsMenu = true
        window.level = .floating
        window.isOpaque = false
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.setContentSize(hiddenWindowSize)
        window.setFrameOrigin(hiddenWindowOrigin)
    }
}

struct HiddenSettingsBridgeView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(
                width: SettingsSceneBridge.keepaliveSceneSize.width,
                height: SettingsSceneBridge.keepaliveSceneSize.height
            )
            .onReceive(NotificationCenter.default.publisher(for: SettingsSceneBridge.openNotification)) { _ in
                openSettings()
            }
            .onAppear {
                SettingsSceneBridge.configureKeepaliveWindowIfNeeded()
            }
    }
}
