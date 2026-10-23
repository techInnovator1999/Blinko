import Foundation
import Observation
import Sparkle

/// Sparkle auto-updates. Releases + `appcast.xml` live on GitHub Releases
/// (see scripts/publish.sh); updates are EdDSA-signed and verified against SUPublicEDKey.
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    /// False for local builds whose feed still points at the placeholder repository.
    let isConfigured: Bool

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        isConfigured = !feed.isEmpty && !feed.contains("/OWNER/")
        controller = isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        canCheckObservation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
