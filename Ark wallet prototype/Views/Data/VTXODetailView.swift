//
//  VTXODetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import AppKit

struct VTXODetailView: View {
    let vtxo: VTXOModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    // VTXO Icon and Type
                    HStack {
                        Image(systemName: vtxo.state.iconName)
                            .font(.system(size: 40))
                            .foregroundColor(vtxo.state.iconColor)
                        
                        VStack(alignment: .leading) {
                            Text("VTXO")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(vtxo.state.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Amount
                    Text(vtxo.formattedAmount)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // State Badge
                    HStack {
                        Text(vtxo.state.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(vtxo.state.textColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(vtxo.state.backgroundColor)
                            .clipShape(Capsule())
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Details Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("VTXO Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        // Outpoint (ID)
                        DetailRow(
                            title: "Outpoint",
                            value: vtxo.outpoint,
                            isCopyable: true
                        )
                        
                        // Transaction ID
                        DetailRow(
                            title: "Transaction ID",
                            value: vtxo.txid,
                            isCopyable: true
                        )
                        
                        // Output Index
                        DetailRow(
                            title: "Output Index",
                            value: String(vtxo.vout)
                        )
                        
                        // Policy Type
                        DetailRow(
                            title: "Policy Type",
                            value: vtxo.policyType.displayName
                        )
                        
                        // State
                        DetailRow(
                            title: "State",
                            value: vtxo.state.displayName
                        )
                    }
                }
                
                Divider()
                
                // Technical Details Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Technical Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        // User Public Key
                        DetailRow(
                            title: "User Public Key",
                            value: vtxo.userPubkey,
                            isCopyable: true
                        )
                        
                        // Server Public Key
                        DetailRow(
                            title: "Server Public Key",
                            value: vtxo.serverPubkey,
                            isCopyable: true
                        )
                        
                        // Chain Anchor
                        DetailRow(
                            title: "Chain Anchor",
                            value: vtxo.chainAnchor,
                            isCopyable: true
                        )
                        
                        // Expiry Height
                        DetailRow(
                            title: "Expiry Height",
                            value: vtxo.expiryHeight.formatted()
                        )
                        
                        // Exit Delta
                        DetailRow(
                            title: "Exit Delta",
                            value: String(vtxo.exitDelta)
                        )
                        
                        // Exit Depth
                        DetailRow(
                            title: "Exit Depth",
                            value: String(vtxo.exitDepth)
                        )
                        
                        // Arkoor Depth
                        DetailRow(
                            title: "Arkoor Depth",
                            value: String(vtxo.arkoorDepth)
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("VTXO Details")
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Extensions to provide display properties for VTXOState and PolicyType
extension VTXOState {
    var displayName: String {
        switch self {
        case .unregisteredBoard:
            return "Unregistered Board"
        case .registeredBoard:
            return "Registered Board"
        case .spent:
            return "Spent"
        case .pending:
            return "Pending"
        case .spendable:
            return "Spendable"
        }
    }
    
    var iconName: String {
        switch self {
        case .unregisteredBoard:
            return "clock.arrow.circlepath"
        case .registeredBoard:
            return "checkmark.circle"
        case .spent:
            return "xmark.circle"
        case .pending:
            return "hourglass"
        case .spendable:
            return "bitcoinsign.circle"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .unregisteredBoard:
            return .orange
        case .registeredBoard:
            return .green
        case .spent:
            return .gray
        case .pending:
            return .blue
        case .spendable:
            return .green
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .unregisteredBoard:
            return .orange.opacity(0.2)
        case .registeredBoard:
            return .green.opacity(0.2)
        case .spent:
            return .gray.opacity(0.2)
        case .pending:
            return .blue.opacity(0.2)
        case .spendable:
            return .green.opacity(0.3)
        }
    }
    
    var textColor: Color {
        switch self {
        case .unregisteredBoard:
            return .orange
        case .registeredBoard:
            return .green
        case .spent:
            return .gray
        case .pending:
            return .blue
        case .spendable:
            return .green
        }
    }
}

extension PolicyType {
    var displayName: String {
        switch self {
        case .pubkey:
            return "Public Key"
        case .multisig:
            return "Multisig"
        }
    }
}

#Preview {
    NavigationStack {
        VTXODetailView(
            vtxo: VTXOModel.mockVTXOs()[0]
        )
    }
}
