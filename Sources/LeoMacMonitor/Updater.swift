//
//  File:      Updater.swift
//  Created:   2026-06-19
//  Updated:   2026-06-19
//  Developer: Leo Yuan
//  Overview:  Sparkle auto-update wrapper. The self-distributed (non-App-Store) app checks a
//             GitHub-Releases appcast for new signed/notarized DMGs and can install them.
//  Notes:     Only starts when running from a real .app bundle — in dev (`swift run`) there is
//             no bundle to update and no Sparkle Info.plist keys (SUFeedURL / SUPublicEDKey),
//             so it stays inert and "Check for Updates" is disabled. Sparkle reads its config
//             from Info.plist (injected by scripts/package.sh) and verifies updates with the
//             EdDSA public key whose private half lives in the developer's keychain.
//
import SwiftUI
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController?
    /// True only in the packaged .app, where Sparkle can actually run.
    let canCheck: Bool

    private init() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            controller = SPUStandardUpdaterController(startingUpdater: true,
                                                     updaterDelegate: nil, userDriverDelegate: nil)
            canCheck = true
        } else {
            controller = nil
            canCheck = false
        }
    }

    func checkForUpdates() { controller?.updater.checkForUpdates() }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
