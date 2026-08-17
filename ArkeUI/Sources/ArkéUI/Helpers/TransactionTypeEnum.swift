//
//  TransactionTypeModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

public enum TransactionTypeEnum: Codable, Equatable, Sendable {
    case sent
    case received
    case transfer
    case pending
    
    public var displayName: String {
        switch self {
        case .sent: return L10n.transactionSent
        case .received: return L10n.transactionReceived
        case .transfer: return String(localized: "transaction_transfer", defaultValue: "Transfer", bundle: .module)
        case .pending: return String(localized: "transaction_type_pending", defaultValue: "Pending", bundle: .module)
        }
    }
    
    public var iconName: String {
        switch self {
        case .sent: return "arrow.up"
        case .received: return "arrow.down"
        case .transfer: return "repeat"
        case .pending: return "clock"
        }
    }
    
    public var iconColor: Color {
        switch self {
        case .sent: return .gray
        case .received: return .Arke.green
        case .transfer: return .gray
        case .pending: return .Arke.blue
        }
    }
    
    public var amountColor: Color {
        switch self {
        case .sent: return .primary
        case .received: return .Arke.green
        case .transfer: return .gray
        case .pending: return .Arke.blue
        }
    }
}
