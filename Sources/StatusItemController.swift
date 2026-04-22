import AppKit
import Observation
import SwiftUI

enum PopoverResizeMode: Equatable {
    case ignore
    case immediate
    case deferred(delay: Duration)
}

enum PopoverResizePolicy {
    static let epsilon: CGFloat = 0.5
    static let shrinkDelay: Duration = .milliseconds(120)

    static func mode(
        currentHeight: CGFloat,
        targetHeight: CGFloat,
        isSelectionTransitionActive: Bool = false
    ) -> PopoverResizeMode {
        guard abs(currentHeight - targetHeight) > epsilon else {
            return .ignore
        }

        if targetHeight > currentHeight {
            return .immediate
        }

        if isSelectionTransitionActive {
            return .immediate
        }

        return .deferred(delay: shrinkDelay)
    }
}

enum PopoverOutsideClickPolicy {
    static func shouldCloseForLocalMouseDown(
        eventWindowMatchesPopover: Bool,
        eventWindowMatchesStatusItem: Bool,
        eventLocationInWindow: CGPoint,
        statusButtonFrameInWindow: CGRect
    ) -> Bool {
        if eventWindowMatchesPopover {
            return false
        }

        if eventWindowMatchesStatusItem,
           statusButtonFrameInWindow.contains(eventLocationInWindow) {
            return false
        }

        return true
    }
}

enum PopoverSizing {
    static let frameOverheadEstimate: CGFloat = 28
    static let anchorMargin: CGFloat = 12
}

@MainActor
@Observable
final class MenuHostCoordinator {
    var openSettingsAction: () -> Void = {}
    var quitAction: () -> Void = { NSApplication.shared.terminate(nil) }
    var resizeAction: (CGFloat) -> Void = { _ in }
    var selectionChangeAction: () -> Void = {}
    var availablePopoverHeight: CGFloat?

    func openSettings() {
        openSettingsAction()
    }

    func quit() {
        quitAction()
    }

    func requestPopoverResize(_ height: CGFloat) {
        resizeAction(height)
    }

    func selectionDidChange() {
        selectionChangeAction()
    }
}

@MainActor
final class MenuStatusAppDelegate: NSObject, NSApplicationDelegate {
    private struct Configuration {
        let store: StatusStore
        let benchmarkStore: AIStupidLevelStore
        let indicator: StatusIndicator
        let iconStyle: MenuBarIconStyle
        let statusItemTitle: String
        let openSettings: () -> Void
    }

    private var didFinishLaunching = false
    private var configuration: Configuration?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        installControllerIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func configure(
        store: StatusStore,
        benchmarkStore: AIStupidLevelStore,
        indicator: StatusIndicator,
        iconStyle: MenuBarIconStyle,
        statusItemTitle: String,
        openSettings: @escaping () -> Void
    ) {
        let configuration = Configuration(
            store: store,
            benchmarkStore: benchmarkStore,
            indicator: indicator,
            iconStyle: iconStyle,
            statusItemTitle: statusItemTitle,
            openSettings: openSettings
        )
        self.configuration = configuration

        if let statusItemController {
            apply(configuration: configuration, to: statusItemController)
        } else {
            installControllerIfNeeded()
        }
    }

    private func installControllerIfNeeded() {
        guard didFinishLaunching, statusItemController == nil, let configuration else { return }

        let controller = StatusItemController(
            store: configuration.store,
            benchmarkStore: configuration.benchmarkStore
        )
        statusItemController = controller
        apply(configuration: configuration, to: controller)
    }

    private func apply(configuration: Configuration, to controller: StatusItemController) {
        controller.setOpenSettingsAction(configuration.openSettings)
        controller.updateStatusItem(
            indicator: configuration.indicator,
            style: configuration.iconStyle,
            title: configuration.statusItemTitle
        )
    }
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private static let outsideClickEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
    ]

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let hostCoordinator = MenuHostCoordinator()
    private let hostingController: NSHostingController<LocalizedMenuRootView>
    private var pendingShrinkTask: Task<Void, Never>?
    private var selectionTransitionDeadline: Date?
    private var popoverFrameHeightOverhead: CGFloat = PopoverSizing.frameOverheadEstimate
    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?

    init(store: StatusStore, benchmarkStore: AIStupidLevelStore) {
        hostingController = NSHostingController(
            rootView: LocalizedMenuRootView(
                settings: store.settings,
                store: store,
                benchmarkStore: benchmarkStore,
                hostCoordinator: hostCoordinator
            )
        )
        hostingController.sizingOptions = [.preferredContentSize]
        super.init()
        configureStatusItem()
        configurePopover()
    }

    func setOpenSettingsAction(_ action: @escaping () -> Void) {
        hostCoordinator.openSettingsAction = { [weak self] in
            self?.closePopover()
            action()
        }
    }

    func updateStatusItem(indicator: StatusIndicator, style: MenuBarIconStyle, title: String) {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIconRenderer.image(indicator: indicator, style: style)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover() {
        popover.animates = false
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: MenuContentSizing.width, height: 420)
        popover.contentViewController = hostingController

        hostCoordinator.quitAction = { [weak self] in
            self?.closePopover()
            NSApplication.shared.terminate(nil)
        }
        hostCoordinator.resizeAction = { [weak self] height in
            self?.updatePopoverSize(height: height)
        }
        hostCoordinator.selectionChangeAction = { [weak self] in
            self?.markSelectionTransition()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        updateAvailablePopoverHeight(using: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installOutsideClickMonitors()
    }

    private func closePopover() {
        pendingShrinkTask?.cancel()
        pendingShrinkTask = nil
        removeOutsideClickMonitors()
        popover.performClose(nil)
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.outsideClickEventMask) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopoverFromOutsideMouseDown()
            }
        }

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.outsideClickEventMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalMouseDown(event)
            }
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        Self.removeEventMonitor(globalMouseDownMonitor)
        globalMouseDownMonitor = nil

        Self.removeEventMonitor(localMouseDownMonitor)
        localMouseDownMonitor = nil
    }

    nonisolated private static func removeEventMonitor(_ monitor: Any?) {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
    }

    private func closePopoverFromOutsideMouseDown() {
        guard popover.isShown else {
            removeOutsideClickMonitors()
            return
        }
        closePopover()
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard popover.isShown else {
            removeOutsideClickMonitors()
            return
        }
        guard let eventWindow = event.window else {
            closePopover()
            return
        }

        let popoverWindow = popover.contentViewController?.view.window
        let statusButtonWindow = statusItem.button?.window
        let statusButtonFrameInWindow = statusItem.button.map { $0.convert($0.bounds, to: nil) } ?? .zero

        if PopoverOutsideClickPolicy.shouldCloseForLocalMouseDown(
            eventWindowMatchesPopover: eventWindow === popoverWindow,
            eventWindowMatchesStatusItem: eventWindow === statusButtonWindow,
            eventLocationInWindow: event.locationInWindow,
            statusButtonFrameInWindow: statusButtonFrameInWindow
        ) {
            closePopover()
        }
    }

    private func updatePopoverSize(height: CGFloat) {
        let targetHeight = max(1, ceil(height))
        let targetSize = NSSize(width: MenuContentSizing.width, height: targetHeight)
        let currentHeight = popover.contentSize.height

        pendingShrinkTask?.cancel()
        pendingShrinkTask = nil

        switch PopoverResizePolicy.mode(
            currentHeight: currentHeight,
            targetHeight: targetHeight,
            isSelectionTransitionActive: isSelectionTransitionActive
        ) {
        case .ignore:
            return
        case .immediate:
            applyPopoverSize(targetSize)
        case .deferred(let delay):
            pendingShrinkTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.applyDeferredShrink(targetSize)
            }
        }
    }

    private func applyDeferredShrink(_ targetSize: NSSize) {
        pendingShrinkTask = nil
        applyPopoverSize(targetSize)
    }

    private var isSelectionTransitionActive: Bool {
        guard let selectionTransitionDeadline else { return false }
        if Date() < selectionTransitionDeadline {
            return true
        }
        self.selectionTransitionDeadline = nil
        return false
    }

    private func markSelectionTransition() {
        selectionTransitionDeadline = Date().addingTimeInterval(0.32)
    }

    private func applyPopoverSize(_ targetSize: NSSize) {
        guard abs(popover.contentSize.height - targetSize.height) > PopoverResizePolicy.epsilon else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            popover.contentSize = targetSize
            popover.contentViewController?.preferredContentSize = targetSize
        }
    }

    func popoverDidShow(_ notification: Notification) {
        stabilizeShownPopover()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }

    private func stabilizeShownPopover() {
        hostingController.view.layoutSubtreeIfNeeded()

        if let window = popover.contentViewController?.view.window {
            window.animationBehavior = .utilityWindow
            window.initialFirstResponder = nil
            window.makeFirstResponder(nil)
            popoverFrameHeightOverhead = max(
                PopoverSizing.frameOverheadEstimate,
                ceil(window.frame.height - popover.contentSize.height)
            )
        }

        if let button = statusItem.button {
            updateAvailablePopoverHeight(using: button)
        }

        let preferredHeight = max(
            popover.contentSize.height,
            ceil(hostingController.preferredContentSize.height)
        )
        applyPopoverSize(NSSize(width: MenuContentSizing.width, height: preferredHeight))
    }

    private func updateAvailablePopoverHeight(using button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        let screen = window.screen ?? NSScreen.main
        let screenMinY = screen?.visibleFrame.minY ?? 0
        let availableHeight = buttonFrameOnScreen.minY
            - screenMinY
            - PopoverSizing.anchorMargin
            - popoverFrameHeightOverhead
        let nextAvailableHeight = max(240, floor(availableHeight))
        guard hostCoordinator.availablePopoverHeight != nextAvailableHeight else { return }
        hostCoordinator.availablePopoverHeight = nextAvailableHeight
    }

    deinit {
        pendingShrinkTask?.cancel()
        Self.removeEventMonitor(globalMouseDownMonitor)
        Self.removeEventMonitor(localMouseDownMonitor)
    }
}
