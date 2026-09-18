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

    /// True when iOS prewarmed this process: it was launched long before the
    /// user opened the app, so elapsed-since-anchor includes hours of dwell
    /// and is meaningless as a launch-cost number (journal finding,
    /// 2026-09-18: "App launched · 4.3h").
    private static let isPrewarmed = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"

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
        logger.notice("⏱️ Wallet ready (success: \(initialized), prewarmed: \(isPrewarmed)) \(elapsed, privacy: .public)s after launch anchor")
        // Journal is iOS-only (Background_Activity_Journal.md decision 6);
        // this file also runs on macOS. Prewarmed launches get no elapsed -
        // the anchor-based number would be dwell, not launch cost.
        #if os(iOS)
        BackgroundEventJournal.record(
            .coldLaunch,
            outcome: initialized ? "success" : "failure",
            elapsedMs: isPrewarmed ? nil : Int(Date().timeIntervalSince(processStart) * 1000),
            detail: isPrewarmed ? "prewarmed" : nil
        )
        #endif
    }
}
