//
//  UserSettings.swift
//  Arké
//
//  Created by Claude on 2/6/26.
//

import Foundation

/// Centralized UserDefaults keys for user preferences
extension UserDefaults {
    /// Key for storing balance privacy preference (hide/show balance)
    static let balancePrivacyKey = "balancePrivacyEnabled"
    
    /// Key for storing the network configuration ID (mainnet, signet, etc.)
    static let networkConfigKey = "com.arke.wallet.networkConfigId"
    
    /// Key for storing notifications enabled preference
    static let notificationsEnabledKey = "notifications_enabled"
    
    /// Key for storing proximity sharing permission
    static let proximityPermissionKey = "hasGrantedProximityPermission"
    
    /// Key for storing the archived MCPeerID used for proximity exchange.
    /// Persisting one peer ID per device avoids ghost peers and torn sessions.
    static let proximityPeerIDKey = "com.arke.proximity.peerID"
    
    /// Display name the persisted MCPeerID was created with, so we can
    /// regenerate it if the device name later changes.
    static let proximityPeerIDNameKey = "com.arke.proximity.peerIDName"
    
    /// Key for storing address icons display preference
    static let showAddressIconsKey = "showAddressIcons"

    /// Key for storing the selected app theme (AppTheme raw value)
    static let appThemeKey = "appTheme"

    /// Key recording that this install has completed at least one wallet sync
    /// that reached the server. Once set, an empty local transaction cache at
    /// launch is trustworthy, so the transaction list can skip its skeleton.
    static let initialSyncCompletedKey = "com.arke.wallet.initialSyncCompleted"

    // MARK: Relay registration (RelayRegistrationService.PersistedRegistration)
    //
    // The mailbox authorization the notification relay holds lives 30 days;
    // these let a cold launch know whether it is past the midpoint and must
    // renew, instead of re-minting on every launch. Cleared on unregister,
    // on a relay 401 and by WalletDataCleanupService.

    // `nonisolated`: read by RelayRegistrationService's nonisolated
    // load/persist helpers (so they're unit-testable off the main actor).

    /// SHA-256 hex of the last authorization sent to the relay (never the token)
    nonisolated static let relayAuthHashKey = "com.arke.relay.lastAuthHash"

    /// Expiry of that authorization, `timeIntervalSince1970`
    nonisolated static let relayAuthExpiresAtKey = "com.arke.relay.authExpiresAt"

    /// When the last successful registration happened, `timeIntervalSince1970`
    nonisolated static let relayRegisteredAtKey = "com.arke.relay.lastRegisteredAt"

    /// APNs device token that registration was made with
    nonisolated static let relayRegisteredDeviceTokenKey = "com.arke.relay.lastRegisteredDeviceToken"

    /// Mailbox id that registration was for
    nonisolated static let relayRegisteredMailboxIdKey = "com.arke.relay.lastRegisteredMailboxId"

    /// All relay registration keys, for wipe paths
    nonisolated static let relayRegistrationKeys: [String] = [
        relayAuthHashKey, relayAuthExpiresAtKey, relayRegisteredAtKey,
        relayRegisteredDeviceTokenKey, relayRegisteredMailboxIdKey
    ]
}
