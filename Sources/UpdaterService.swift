import Foundation
import Sparkle

enum UpdaterAvailability: Equatable {
    case available
    case missingFeedURL
    case missingPublicKey
    case buildProducts
    case notInstalledToApplications

    var diagnosticMessage: String? {
        switch self {
        case .available:
            nil
        case .missingFeedURL:
            "Missing SUFeedURL in this build, so MenuStatus cannot check for updates."
        case .missingPublicKey:
            "Missing SUPublicEDKey in this build, so MenuStatus cannot verify updates."
        case .buildProducts:
            "In-app updates are unavailable in local build products."
        case .notInstalledToApplications:
            "Install MenuStatus to /Applications to enable in-app updates."
        }
    }
}

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
        availability == .available
    }

    var availability: UpdaterAvailability {
        if isBuildProductsBundle {
            return .buildProducts
        }
        if !isInstalledToApplications {
            return .notInstalledToApplications
        }
        if feedURLString.isEmpty {
            return .missingFeedURL
        }
        if publicEDKey.isEmpty {
            return .missingPublicKey
        }
        return .available
    }

    private var isInstalledToApplications: Bool {
        guard isAppBundle else { return false }
        let normalizedPath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        return normalizedPath.hasPrefix("/Applications/")
    }

    private var isAppBundle: Bool {
        URL(fileURLWithPath: bundlePath).pathExtension == "app"
    }

    private var isBuildProductsBundle: Bool {
        let normalizedPath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        let blockedSegments = [
            "/.build/",
            "/Derived/",
            "/DerivedData/",
            "/Build/Products/"
        ]

        return blockedSegments.contains { normalizedPath.contains($0) }
    }
}

@Observable final class UpdaterService {
    private let configuration: UpdaterConfiguration
    private let updaterController: SPUStandardUpdaterController?
    private let updater: SPUUpdater?
    private let startupErrorMessage: String?

    init(bundle: Bundle = .main) {
        self.configuration = UpdaterConfiguration(bundle: bundle)
        guard configuration.isAvailable else {
            self.updaterController = nil
            self.updater = nil
            self.startupErrorMessage = nil
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
            self.startupErrorMessage = nil
        } catch {
            self.startupErrorMessage = "Sparkle failed to start in this build."
            print("Sparkle failed to start: \(error)")
        }
    }

    var availability: UpdaterAvailability {
        configuration.availability
    }

    var diagnosticMessage: String? {
        if let startupErrorMessage {
            return startupErrorMessage
        }
        if availability != .available {
            return availability.diagnosticMessage
        }
        if !(updater?.canCheckForUpdates ?? false) {
            return "Update checks are temporarily unavailable."
        }
        return nil
    }

    var isAvailable: Bool {
        availability == .available && updater != nil && startupErrorMessage == nil
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
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
