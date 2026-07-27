//
//  LaunchTiming.swift
//  Arké
//
//  Created by Christoph on 7/27/26.
//

import Foundation
import OSLog

/// Wall-clock anchor for the launch-timing field data the background execution
/// plan needs (cold launch → wallet ready; see Background_Execution.md, Phase 1).
/// Those numbers decide whether a ~30s BGAppRefreshTask window can fit a full
/// maintenance pass after a cold launch, or whether heavy steps must move to a
/// BGProcessingTask.
@MainActor
enum LaunchTiming {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "LaunchTiming")

    /// Initialized on first touch — anchor() must run as the first app code so
    /// this lands as close to real process start as Swift statics allow.
    private static let processStart = Date()

    private static var walletReadyLogged = false

    /// Call as early as possible in the app's init so `processStart` anchors
    /// near the actual launch rather than at first use.
    static func anchor() {
        _ = processStart
    }

    /// Logs the launch → wallet-ready duration. The first call per process is
    /// the cold-launch number (notice level, so it persists to disk and shows
    /// up in sysdiagnose/TestFlight logs); later re-initializations log at
    /// debug level.
    static func logWalletReady(initialized: Bool) {
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(processStart))
        if walletReadyLogged {
            logger.debug("⏱️ Wallet re-initialized (success: \(initialized)) \(elapsed, privacy: .public)s after launch anchor")
            return
        }
        walletReadyLogged = true
        logger.notice("⏱️ Wallet ready (success: \(initialized)) \(elapsed, privacy: .public)s after launch anchor")
    }
}
