//
//  BitcoinNetwork.swift
//  ArkéUI
//
//  Moved into ArkéUI as a pure presentation value type (no SwiftData/Bark).
//  The `NetworkConfig`-based `matches(_:)` helper stays app-side as an extension,
//  since `NetworkConfig` does not move into the package.
//

import Foundation

// MARK: - Bitcoin Network Types

public enum BitcoinNetwork: String, CaseIterable, Codable, Sendable {
    case mainnet = "mainnet"
    case testnet = "testnet"
    case signet = "signet"
    case regtest = "regtest"

    public var displayName: String {
        switch self {
        case .mainnet:
            return "Bitcoin Mainnet"
        case .testnet:
            return "Bitcoin Testnet"
        case .signet:
            return "Bitcoin Signet"
        case .regtest:
            return "Bitcoin Regtest"
        }
    }

    /// Initialize from NetworkConfig networkType string
    public init?(networkType: String) {
        switch networkType.lowercased() {
        case "mainnet":
            self = .mainnet
        case "testnet":
            self = .testnet
        case "signet":
            self = .signet
        case "regtest":
            self = .regtest
        default:
            return nil
        }
    }
}
