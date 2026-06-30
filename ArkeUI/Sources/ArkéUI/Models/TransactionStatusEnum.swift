//
//  TransactionStatusEnum.swift
//  ArkéUI
//
//  Created by Christoph on 10/16/25.
//  Moved into ArkéUI as a pure presentation value type (no SwiftData/Bark).
//

import SwiftUI

public enum TransactionStatusEnum: Codable, Equatable, Sendable {
    case confirmed
    case pending
    case failed

    public var displayName: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .pending: return "Pending"
        case .failed: return "Failed"
        }
    }

    public var backgroundColor: Color {
        switch self {
        case .confirmed: return .Arke.green.opacity(0.2)
        case .pending: return .Arke.orange.opacity(0.2)
        case .failed: return .Arke.red.opacity(0.2)
        }
    }

    public var textColor: Color {
        switch self {
        case .confirmed: return .Arke.green
        case .pending: return .Arke.orange
        case .failed: return .Arke.red
        }
    }
}
