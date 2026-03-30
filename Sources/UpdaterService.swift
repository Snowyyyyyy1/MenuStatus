import Foundation
import Sparkle

@Observable final class UpdaterService {
    let updater: SPUUpdater

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updater = controller.updater

        // Only start if feed URL is configured
        if let feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
           !feedURL.isEmpty {
            do {
                try updater.start()
            } catch {
                print("Sparkle failed to start: \(error)")
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
}
