//
//  TransactionTypeModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

enum TransactionStatusEnum: Codable, Equatable, Sendable {
    case confirmed
    case pending
    case failed
    
    var displayName: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .pending: return "Pending"
        case .failed: return "Failed"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .confirmed: return .green.opacity(0.2)
        case .pending: return .orange.opacity(0.2)
        case .failed: return .red.opacity(0.2)
        }
    }
    
    var textColor: Color {
        switch self {
        case .confirmed: return .green
        case .pending: return .orange
        case .failed: return .red
        }
    }
}
