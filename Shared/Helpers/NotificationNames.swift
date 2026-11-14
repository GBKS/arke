import Foundation

extension Notification.Name {
    /// Posted when device is demoted from primary to secondary
    static let deviceDemotedFromPrimary = Notification.Name("deviceDemotedFromPrimary")
    /// This device's own registry row disappeared while it ran as primary:
    /// another device unlinked or wiped it (Device_Linking.md §11.6). Closes
    /// bark like a demotion but writes no final backup — a removed device
    /// must not write into the account's backup slot.
    static let deviceUnlinkedWhileRunning = Notification.Name("deviceUnlinkedWhileRunning")
    
    /// Posted when device is promoted from secondary to primary
    static let devicePromotedToPrimary = Notification.Name("devicePromotedToPrimary")
    
    /// Posted when no primary device is detected
    static let showNoPrimaryDeviceBanner = Notification.Name("showNoPrimaryDeviceBanner")
}
