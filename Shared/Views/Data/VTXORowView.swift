//
//  VTXORowView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import ArkeUI

struct VTXORowView: View {
    let vtxo: VTXOModel
    let isSelected: Bool
    let latestBlockHeight: Int?
    @Environment(WalletManager.self) private var walletManager
    
    private var blocksUntilExpiry: Int? {
        guard let latestBlockHeight = latestBlockHeight else { return nil }
        return vtxo.expiryHeight - latestBlockHeight
    }
    
    private var isExpired: Bool {
        guard let blocksUntilExpiry = blocksUntilExpiry else { return false }
        return blocksUntilExpiry <= 0
    }
    
    private var isNearExpiry: Bool {
        guard let blocksUntilExpiry = blocksUntilExpiry else { return false }
        // Check if expiry is within 24 hours based on block time (~10 minutes per block)
        let secondsUntilExpiry = blocksUntilExpiry * BlockTimeFormatter.secondsPerBlock
        let hoursUntilExpiry = secondsUntilExpiry / 3600
        return blocksUntilExpiry > 0 && hoursUntilExpiry <= 24
    }

    private var expiryText: String {
        guard let blocksUntilExpiry = blocksUntilExpiry else {
            return "Block \(vtxo.expiryHeight)"
        }

        if isExpired {
            return "Expired \(BlockTimeFormatter.duration(forBlocks: blocksUntilExpiry)) ago"
        } else {
            return "Expires in ~\(BlockTimeFormatter.duration(forBlocks: blocksUntilExpiry))"
        }
    }

    private var expiryColor: Color {
        if isExpired {
            return .Arke.red
        } else if isNearExpiry {
            return .Arke.orange
        } else {
            return .secondary
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(vtxo.formattedAmount)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                // VTXO State Badge
                HStack(spacing: 4) {
                    /*
                    Image(systemName: vtxo.state.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(vtxo.state.iconColor)
                     */
                    
                    Text(vtxo.state.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(vtxo.state.textColor)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(expiryText)
                    .font(.body)
                    .foregroundStyle(expiryColor)
                    .lineLimit(1)
                
                Text(vtxo.shortTxid)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .cornerRadius(15)
    }
}
