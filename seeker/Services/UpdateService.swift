import Foundation
import Observation
import Sparkle

enum UpdateResumeState {
    private static let targetVersionKey = "update.resume.targetVersion"
    private static let wasRunningKey = "update.resume.wasRunning"

    static var currentBundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static func record(
        targetVersion: String,
        wasRunning: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard wasRunning else {
            clear(defaults: defaults)
            return
        }

        defaults.set(targetVersion, forKey: targetVersionKey)
        defaults.set(true, forKey: wasRunningKey)
    }

    static func consumeIfMatching(
        currentVersion: String = currentBundleVersion,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defer { clear(defaults: defaults) }
        guard defaults.bool(forKey: wasRunningKey) else { return false }
        return defaults.string(forKey: targetVersionKey) == currentVersion
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: targetVersionKey)
        defaults.removeObject(forKey: wasRunningKey)
    }
}

@MainActor
@Observable
final class UpdateService: NSObject, SPUUpdaterDelegate {
    #if DEBUG
    static let updatesEnabled = false
    #else
    static let updatesEnabled = true
    #endif

    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private let isSeekerRunning: () -> Bool

    init(isSeekerRunning: @escaping () -> Bool) {
        self.isSeekerRunning = isSeekerRunning
        super.init()

        guard Self.updatesEnabled else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            let canCheckForUpdates = updater.canCheckForUpdates
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = canCheckForUpdates
            }
        }
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController?.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        UpdateResumeState.record(
            targetVersion: item.versionString,
            wasRunning: isSeekerRunning()
        )
    }
}
