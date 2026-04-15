import Foundation
import Sparkle

struct UpdaterConfiguration: Equatable {
    let feedURLString: String
    let publicEDKey: String
    let bundlePath: String

    init(feedURLString: String, publicEDKey: String, bundlePath: String) {
        self.feedURLString = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicEDKey = publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundlePath = bundlePath
    }

    init(bundle: Bundle = .main) {
        self.init(
            feedURLString: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "",
            publicEDKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "",
            bundlePath: bundle.bundleURL.path
        )
    }

    var isAvailable: Bool {
        hasRequiredMetadata && isInstalledAppBundle
    }

    private var hasRequiredMetadata: Bool {
        !feedURLString.isEmpty && !publicEDKey.isEmpty
    }

    private var isInstalledAppBundle: Bool {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        guard bundleURL.pathExtension == "app" else { return false }

        let normalizedPath = bundleURL.standardizedFileURL.path
        let blockedSegments = [
            "/.build/",
            "/Derived/",
            "/DerivedData/",
            "/Build/Products/"
        ]

        return blockedSegments.allSatisfy { !normalizedPath.contains($0) }
    }
}

@Observable final class UpdaterService {
    private let configuration: UpdaterConfiguration
    private let updaterController: SPUStandardUpdaterController?
    private let updater: SPUUpdater?

    init(bundle: Bundle = .main) {
        self.configuration = UpdaterConfiguration(bundle: bundle)
        guard configuration.isAvailable else {
            self.updaterController = nil
            self.updater = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self.updater = controller.updater

        do {
            try controller.updater.start()
        } catch {
            print("Sparkle failed to start: \(error)")
        }
    }

    var isAvailable: Bool {
        configuration.isAvailable && updater != nil
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }
}
