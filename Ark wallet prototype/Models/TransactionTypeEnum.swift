//
//  TransactionTypeModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

enum TransactionTypeEnum: Codable {
    case sent
    case received
    case pending
    
    var displayName: String {
        switch self {
        case .sent: return "Sent"
        case .received: return "Received"
        case .pending: return "Pending"
        }
    }
    
    var iconName: String {
        switch self {
        case .sent: return "arrow.up"
        case .received: return "arrow.down"
        case .pending: return "clock"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .sent: return .primary
        case .received: return .green
        case .pending: return .orange
        }
    }
    
    var amountColor: Color {
        switch self {
        case .sent: return .primary
        case .received: return .green
        case .pending: return .orange
        }
    }
}
