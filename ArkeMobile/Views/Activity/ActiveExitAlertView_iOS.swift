//
//  ActiveExitAlertView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

import SwiftUI
import Bark
import ArkeUI

struct ActiveExitAlertView_iOS: View {
    let exit: ExitVtxo
    let currentBlockHeight: Int
    let claimableHeight: Int?
    let onTap: () -> Void
    
    private var statusColor: Color {
        if exit.isClaimable {
            return .Arke.blue
        }
        return exit.stateColor
    }
    
    private var statusIcon: String {
        exit.stateIcon
    }
    
    private var statusMessage: String {
        if exit.isClaimable {
            return "Ready to withdraw"
        }
        
        if let claimableHeight = claimableHeight {
            let blocksRemaining = max(0, claimableHeight - currentBlockHeight)
            if blocksRemaining > 0 {
                return "\(blocksRemaining) blocks remaining"
            }
        }
        
        return exit.stateDisplayName
    }
    
    private var shouldPulse: Bool {
        exit.isClaimable
    }
    
    private var titleMessage: String {
        if exit.isClaimable {
            return "Finishing your forced move"
        }

        // Extract the state case name
        let stateString = String(describing: exit.state)
        let caseName: String
        if let parenIndex = stateString.firstIndex(of: "(") {
            caseName = String(stateString[..<parenIndex]).lowercased()
        } else {
            caseName = stateString.lowercased()
        }

        switch caseName {
        case "start", "processing":
            return "Forced move in progress"
        case "awaitingdelta":
            return "Forced move in progress"
        case "claiminprogress":
            return "Finishing your forced move"
        case "claimed":
            return "Forced move complete"
        default:
            return "Forced move in progress"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: statusIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: shouldPulse)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(titleMessage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        // Status badge
                        /*
                        Text(exit.stateDisplayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15))
                            .clipShape(Capsule())
                         */
                    }
                    
                    HStack(spacing: 8) {
                        Text(exit.formattedAmount)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        /*
                        Text("symbol_bullet")
                            .foregroundStyle(.tertiary)
                        
                        Text(statusMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                         */
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
