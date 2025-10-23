//
//  ReceiveBalanceType.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import Foundation

extension ReceiveView {
    enum BalanceType: String, CaseIterable {
        case payments = "Payments"
        case savings = "Savings"
        case paymentsAndSavings = "Payments + Savings"
        case lightning = "Payments via Lightning"
        
        var description: String {
            switch self {
            case .payments:
                return "Fast & low fees · Ark network"
            case .savings:
                return "Best security · Bitcoin network"
            case .paymentsAndSavings:
                return "Share both, let the sender choose"
            case .lightning:
                return "Fast & low fees · Lightning network"
            }
        }
    }
}