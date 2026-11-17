import Foundation

extension Notification.Name {
    /// Posted when device is demoted from primary to secondary. Post it
    /// through `Notification.deviceDemoted(reason:)`: the userInfo names the
    /// `MigrationCloseReason`, which decides whether the close writes the
    /// hand-over backup (only the guided demote does).
    static let deviceDemotedFromPrimary = Notification.Name("deviceDemotedFromPrimary")
    /// This device's own registry row disappeared while it ran as primary:
    /// another device unlinked or wiped it (Device_Linking.md §11.6). Closes
    /// bark like a demotion but writes no final backup — a removed device
    /// must not write into the account's backup slot.
    static let deviceUnlinkedWhileRunning = Notification.Name("deviceUnlinkedWhileRunning")
    /// This device was unlinked while running and is ready to leave the
    /// wallet UI: posted after the wallet closed (ex-primary) or at once (a
    /// secondary had nothing to close). The main view re-runs detection so
    /// the device lands on the link screen.
    static let walletClosedAfterUnlink = Notification.Name("walletClosedAfterUnlink")
    
    /// Posted when device is promoted from secondary to primary
    static let devicePromotedToPrimary = Notification.Name("devicePromotedToPrimary")
    
    /// Posted when no primary device is detected
    static let showNoPrimaryDeviceBanner = Notification.Name("showNoPrimaryDeviceBanner")
}

extension Notification {
    private static let migrationCloseReasonKey = "migrationCloseReason"

    /// The demotion notification with its close reason attached
    static func deviceDemoted(reason: MigrationCloseReason) -> Notification {
        Notification(name: .deviceDemotedFromPrimary, object: nil,
                     userInfo: [migrationCloseReasonKey: reason.rawValue])
    }

    /// The close reason a `.deviceDemotedFromPrimary` poster attached. A
    /// post without one is read as the hand-over, the behaviour every poster
    /// had before the reason existed.
    var migrationCloseReason: MigrationCloseReason {
        (userInfo?[Self.migrationCloseReasonKey] as? String).flatMap(MigrationCloseReason.init(rawValue:)) ?? .handover
    }
}
