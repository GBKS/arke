//
//  BackgroundActivityAssertion.swift
//  Arké
//
//  Created by Assistant on 9/24/26.
//

import Foundation
import os

#if os(iOS)
import UIKit
#endif

/// Runs `operation` while the app holds a task assertion, so the system can't
/// suspend the process in the middle of it.
///
/// Why this exists: a SwiftData save, a CloudKit mirroring pass, or a bark
/// database open holds a SQLite (or file) lock for its duration, and a process
/// that gets suspended while holding one is killed outright —
/// `Termination Reason: RUNNINGBOARD 0xdead10cc`. Two of the three TestFlight
/// crash signatures on build 23 were that kill, both on background runs: a
/// `registerCurrentDevice` save and a wallet-directory write. Apple's guidance
/// is to take the assertion *before* starting store or file work that must not
/// be interrupted, which is what this wrapper does.
///
/// The assertion is best-effort by design. If the system refuses to grant one
/// (`.invalid`, e.g. background execution isn't possible right now) the work
/// still runs — unprotected, exactly as it did before this existed. Callers
/// therefore never need to handle a "couldn't protect it" case.
///
/// No-op off iOS: nothing suspends a Mac app this way.
@MainActor
func withBackgroundActivityAssertion<T>(
    _ name: String,
    operation: () async throws -> T
) async rethrows -> T {
    #if os(iOS)
    let assertion = BackgroundActivityAssertion(name: name)
    defer { assertion.end() }
    return try await operation()
    #else
    return try await operation()
    #endif
}

#if os(iOS)
/// A balanced `beginBackgroundTask`/`endBackgroundTask` pair. Prefer
/// `withBackgroundActivityAssertion(_:operation:)`; use this directly only
/// when the protected span can't be expressed as a single closure.
@MainActor
final class BackgroundActivityAssertion {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.arke",
        category: "BackgroundAssertion"
    )

    private let name: String
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        self.name = name

        // The expiration handler is mandatory, not advisory: an assertion that
        // is never ended is itself a termination cause. The system runs it on
        // the main thread, briefly blocking suspension — so ending there is
        // the last chance to let the process suspend cleanly.
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Self.logger.warning("⏳ Background assertion '\(name, privacy: .public)' expired before its work finished")
            self?.end()
        }

        if identifier == .invalid {
            Self.logger.info("ℹ️ Background assertion '\(name, privacy: .public)' not granted — work runs unprotected")
        }
    }

    /// Idempotent: safe to call from both the expiration handler and the
    /// normal completion path.
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
