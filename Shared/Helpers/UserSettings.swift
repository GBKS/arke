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

    /// Key recording that this install has completed at least one wallet sync
    /// that reached the server. Once set, an empty local transaction cache at
    /// launch is trustworthy, so the transaction list can skip its skeleton.
    static let initialSyncCompletedKey = "com.arke.wallet.initialSyncCompleted"
}
