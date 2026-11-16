//
//  HandoverReadiness.swift
//  Arké
//
//  Created by Assistant on 11/14/26.
//

import Foundation

/// The state machine behind flow 4.3 branch A, the deliberate primary
/// handover (Device_Linking.md §4.3, §14). Pure so the order of the two
/// conditions is pinned by a test, not by reading the view.
///
/// Why two conditions, in this order: the old primary writes its flag and
/// row first, then shuts bark down and writes the final backup. Promoting on
/// the flag alone would restore whatever backup iCloud Drive happened to hold,
/// which is the stale-state hazard; promoting before the row flips would be
/// refused by the registry anyway.
nonisolated enum HandoverReadiness: Equatable, Sendable {
    /// The other device has not started: its row still says primary and its
    /// flag is still true (or unknown)
    case waitingForHandover
    /// The flag flipped (fast signal) but the registry row has not yet, so
    /// promotion would still be refused
    case handoverStarted
    /// Row says not primary; waiting for a backup newer than the flip to be
    /// downloaded here
    case waitingForBackup
    /// Promote now
    case ready

    static func evaluate(
        otherFlag: Bool?,
        otherRowIsPrimary: Bool,
        backupReady: Bool
    ) -> HandoverReadiness {
        if otherRowIsPrimary {
            return otherFlag == false ? .handoverStarted : .waitingForHandover
        }
        return backupReady ? .ready : .waitingForBackup
    }
}
