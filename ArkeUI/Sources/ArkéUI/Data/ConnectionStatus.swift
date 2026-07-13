//
//  ConnectionStatus.swift
//  Ark wallet prototype
//
//  Created by Christoph on 1/6/26.
//

import Foundation

/// ASP connection quality levels
public enum ConnectionQuality: String, Codable, CaseIterable, Sendable {
    case excellent = "excellent"
    case good = "good"
    case poor = "poor"
    case disconnected = "disconnected"
}

public extension ConnectionQuality {
    var displayName: String {
        switch self {
        case .excellent:
            return String(localized: "connection_quality_excellent", bundle: .module)
        case .good:
            return String(localized: "connection_quality_good", bundle: .module)
        case .poor:
            return String(localized: "connection_quality_poor", bundle: .module)
        case .disconnected:
            return String(localized: "connection_quality_disconnected", bundle: .module)
        }
    }
    
    var iconName: String {
        switch self {
        case .excellent:
            return "wifi"
        case .good:
            return "wifi"
        case .poor:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        }
    }
    
    /// Determine quality from latency (in milliseconds)
    static func from(latencyMs: Double?) -> ConnectionQuality {
        guard let latency = latencyMs else {
            return .disconnected
        }
        
        if latency < 200 {
            return .excellent
        } else if latency < 500 {
            return .good
        } else {
            return .poor
        }
    }
    
    /// Determine quality from time since last successful sync
    static func from(lastSuccessfulSync: Date?) -> ConnectionQuality {
        guard let lastSync = lastSuccessfulSync else {
            return .disconnected
        }
        
        let secondsSinceSync = Date().timeIntervalSince(lastSync)
        
        if secondsSinceSync < 60 {
            return .excellent
        } else if secondsSinceSync < 300 { // 5 minutes
            return .good
        } else if secondsSinceSync < 900 { // 15 minutes
            return .poor
        } else {
            return .disconnected
        }
    }
    
    public var canPerformCollaborativeOperations: Bool {
        switch self {
        case .excellent, .good:
            return true
        case .poor:
            return true // Can try, but might be slow
        case .disconnected:
            return false
        }
    }
}

/// Why the wallet is in read-only mode
public enum ReadOnlyReason: Sendable, Equatable {
    /// Another device is the primary device; this one views synced data
    case notPrimary
    /// The wallet key hasn't reached this device yet (iCloud Keychain sync pending)
    case seedNotSynced
}

/// Connection status information (not persisted - computed/updated on each refresh)
public struct ConnectionStatus: Sendable {
    public var isConnected: Bool
    public var quality: ConnectionQuality
    public var lastSuccessfulSync: Date?
    public var reconnectionAttempts: Int
    public var lastError: String?
    public var isReadOnlyMode: Bool
    /// Set when `isReadOnlyMode` is true; nil otherwise
    public var readOnlyReason: ReadOnlyReason?

    public init(
        isConnected: Bool = false,
        quality: ConnectionQuality = .disconnected,
        lastSuccessfulSync: Date? = nil,
        reconnectionAttempts: Int = 0,
        lastError: String? = nil,
        isReadOnlyMode: Bool = false,
        readOnlyReason: ReadOnlyReason? = nil
    ) {
        self.isConnected = isConnected
        self.quality = quality
        self.lastSuccessfulSync = lastSuccessfulSync
        self.reconnectionAttempts = reconnectionAttempts
        self.lastError = lastError
        self.isReadOnlyMode = isReadOnlyMode
        self.readOnlyReason = readOnlyReason
    }
    
    // MARK: - Display Properties
    
    public var statusMessage: String {
        if isReadOnlyMode {
            return String(localized: "status_readonly_mode", bundle: .module)
        }

        if isConnected {
            switch quality {
            case .excellent:
                return String(localized: "status_connected", bundle: .module)
            case .good:
                return String(localized: "status_connected", bundle: .module)
            case .poor:
                return String(localized: "status_poor_connection", bundle: .module)
            case .disconnected:
                return String(localized: "status_disconnected", bundle: .module)
            }
        } else {
            if reconnectionAttempts > 0 {
                return String(localized: "status_reconnecting_attempt \(reconnectionAttempts)", bundle: .module)
            } else {
                return String(localized: "status_disconnected", bundle: .module)
            }
        }
    }
    
    public var detailedMessage: String? {
        if let lastSync = lastSuccessfulSync {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return String(localized: "status_last_synced \(formatter.localizedString(for: lastSync, relativeTo: Date()))", bundle: .module)
        }
        return nil
    }
    
    public var showWarning: Bool {
        // Read-only mode should show indicator but not as a warning
        if isReadOnlyMode {
            return false
        }
        return !isConnected || quality == .poor || quality == .disconnected
    }

    public var shouldShowIndicator: Bool {
        return isReadOnlyMode || !isConnected || quality == .poor || quality == .disconnected
    }
    
    public var canPerformCollaborativeOperations: Bool {
        return isConnected && quality.canPerformCollaborativeOperations
    }
    
    // MARK: - Update Methods
    
    public mutating func markConnected(quality: ConnectionQuality = .excellent) {
        self.isConnected = true
        self.quality = quality
        self.lastSuccessfulSync = Date()
        self.reconnectionAttempts = 0
        self.lastError = nil
    }
    
    public mutating func markDisconnected(error: String? = nil) {
        self.isConnected = false
        self.quality = .disconnected
        self.lastError = error
    }
    
    public mutating func incrementReconnectionAttempt() {
        self.reconnectionAttempts += 1
    }
    
    public mutating func updateQuality(from lastSync: Date?) {
        self.quality = ConnectionQuality.from(lastSuccessfulSync: lastSync)
    }
}
