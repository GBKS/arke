//
//  FeeScheduleView_iOS.swift
//  Arké
//
//  Created by Claude on 04/17/26.
//

import SwiftUI
import ArkeUI

struct FeeScheduleView_iOS: View {
    @Environment(WalletManager.self) private var manager
    
    var body: some View {
        Group {
            if let feeSchedule = manager.arkInfo?.feeSchedule {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("fee_schedule_help")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider()
                        
                        // Board (Receiving on-chain)
                        FeeCard(
                            title: "Move to payments",
                            subtitle: "Receiving on-chain funds",
                            icon: nil,
                            iconBackground: "wallet",
                            description: nil,
                            details: boardDetails(feeSchedule.board),
                            isFree: isBoardFree(feeSchedule.board)
                        )
                        
                        Divider()
                        
                        // Offboard (Sending to on-chain)
                        FeeCard(
                            title: "Move to savings",
                            subtitle: "Sending to on-chain address",
                            icon: nil,
                            iconBackground: "safe",
                            description: nil,
                            details: offboardDetails(feeSchedule.offboard),
                            isFree: isOffboardFree(feeSchedule.offboard)
                        )
                        
                        Divider()
                        
                        // Refresh
                        FeeCard(
                            title: "Payments balance refresh",
                            subtitle: "Extending VTXO expiry",
                            icon: "repeat",
                            iconBackground: "card",
                            description: nil,
                            details: refreshDetails(feeSchedule.refresh),
                            isFree: isRefreshFree(feeSchedule.refresh)
                        )
                        
                        Divider()
                        
                        // Lightning Receive
                        FeeCard(
                            title: "Receive lightning payments",
                            subtitle: "Receiving Lightning payments",
                            icon: "bolt.fill",
                            iconBackground: "card",
                            description: nil,
                            details: lightningReceiveDetails(feeSchedule.lightningReceive),
                            isFree: isLightningReceiveFree(feeSchedule.lightningReceive)
                        )
                        
                        Divider()
                        
                        // Lightning Send
                        FeeCard(
                            title: "Send lightning payments",
                            subtitle: "Sending Lightning payments",
                            icon: "bolt.fill",
                            iconBackground: "card",
                            description: nil,
                            details: lightningSendDetails(feeSchedule.lightningSend),
                            isFree: isLightningSendFree(feeSchedule.lightningSend)
                        )
                        
                        // Footer note
                        Text("fee_server_fees_help")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }
            } else {
                ContentUnavailableView(
                    "fee_information_unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("fee_unable_to_load_fee_schedule")
                )
            }
        }
        .navigationTitle("settings_fee_schedule")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Fee Details Helpers
    
    // Convert blocks to approximate time string
    private func blocksToTimeString(_ blocks: UInt32) -> String {
        let minutes = Int(blocks) * 10
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        
        if weeks > 0 {
            return "~\(weeks) week\(weeks == 1 ? "" : "s")"
        } else if days > 0 {
            return "~\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            return "~\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "~\(minutes) min\(minutes == 1 ? "" : "s")"
        }
    }
    
    private func isBoardFree(_ board: BoardFeeStructure) -> Bool {
        return board.minFeeSat == 0 && board.baseFeeSat == 0 && board.ppm == 0
    }
    
    private func isOffboardFree(_ offboard: OffboardFeeStructure) -> Bool {
        return offboard.baseFeeSat == 0 && 
               offboard.fixedAdditionalVb == 0 && 
               offboard.ppmExpiryTable.allSatisfy { $0.ppm == 0 }
    }
    
    private func isRefreshFree(_ refresh: RefreshFeeStructure) -> Bool {
        return refresh.baseFeeSat == 0 && 
               refresh.ppmExpiryTable.allSatisfy { $0.ppm == 0 }
    }
    
    private func isLightningReceiveFree(_ lightningReceive: LightningReceiveFeeStructure) -> Bool {
        return lightningReceive.baseFeeSat == 0 && lightningReceive.ppm == 0
    }
    
    private func isLightningSendFree(_ lightningSend: LightningSendFeeStructure) -> Bool {
        return lightningSend.minFeeSat == 0 && 
               lightningSend.baseFeeSat == 0 && 
               lightningSend.ppmExpiryTable.allSatisfy { $0.ppm == 0 }
    }
    
    private func boardDetails(_ board: BoardFeeStructure) -> [(String, String)] {
        var details: [(String, String)] = []
        
        if board.minFeeSat > 0 {
            details.append(("Minimum Fee", BitcoinFormatter.shared.formatAmount(board.minFeeSat)))
        }
        if board.baseFeeSat > 0 {
            details.append(("Base Fee", BitcoinFormatter.shared.formatAmount(board.baseFeeSat)))
        }
        if board.ppm > 0 {
            let percent = Double(board.ppm) / 10_000
            details.append(("Percentage", "\(String(format: "%.2f", percent))%"))
        }
        
        return details
    }
    
    private func offboardDetails(_ offboard: OffboardFeeStructure) -> [(String, String)] {
        var details: [(String, String)] = []
        
        if offboard.baseFeeSat > 0 {
            details.append(("Base Fee", BitcoinFormatter.shared.formatAmount(offboard.baseFeeSat)))
        }
        if offboard.fixedAdditionalVb > 0 {
            details.append(("Virtual Bytes", "\(offboard.fixedAdditionalVb) vB"))
        }
        
        // Add PPM expiry table
        if !offboard.ppmExpiryTable.isEmpty {
            details.append(("", "Percentage by Expiry"))
            let sortedEntries = offboard.ppmExpiryTable.sorted(by: { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold })
            
            for (index, entry) in sortedEntries.enumerated() {
                let percent = Double(entry.ppm) / 10_000
                
                if index < sortedEntries.count - 1 {
                    // Not the last entry - show "Below X time"
                    let nextThreshold = sortedEntries[index + 1].expiryBlocksThreshold
                    details.append(("Less than \(blocksToTimeString(UInt32(nextThreshold)))", "\(String(format: "%.2f", percent))%"))
                } else {
                    // Last entry - show "≥X time"
                    details.append(("More than \(blocksToTimeString(UInt32(entry.expiryBlocksThreshold)))", "\(String(format: "%.2f", percent))%"))
                }
            }
        }
        
        return details
    }
    
    private func refreshDetails(_ refresh: RefreshFeeStructure) -> [(String, String)] {
        var details: [(String, String)] = []
        
        if refresh.baseFeeSat > 0 {
            details.append(("Base Fee", BitcoinFormatter.shared.formatAmount(refresh.baseFeeSat)))
        }
        
        // Add PPM expiry table
        if !refresh.ppmExpiryTable.isEmpty {
            details.append(("", "Percentage by Expiry"))
            let sortedEntries = refresh.ppmExpiryTable.sorted(by: { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold })
            
            for (index, entry) in sortedEntries.enumerated() {
                let percent = Double(entry.ppm) / 10_000
                
                if index < sortedEntries.count - 1 {
                    // Not the last entry - show "Below X time"
                    let nextThreshold = sortedEntries[index + 1].expiryBlocksThreshold
                    details.append(("Less than \(blocksToTimeString(UInt32(nextThreshold)))", "\(String(format: "%.2f", percent))%"))
                } else {
                    // Last entry - show "≥X time"
                    details.append(("More than \(blocksToTimeString(UInt32(entry.expiryBlocksThreshold)))", "\(String(format: "%.2f", percent))%"))
                }
            }
        }
        
        return details
    }
    
    private func lightningReceiveDetails(_ lightningReceive: LightningReceiveFeeStructure) -> [(String, String)] {
        var details: [(String, String)] = []
        
        if lightningReceive.baseFeeSat > 0 {
            details.append(("Base Fee", BitcoinFormatter.shared.formatAmount(lightningReceive.baseFeeSat)))
        }
        if lightningReceive.ppm > 0 {
            let percent = Double(lightningReceive.ppm) / 10_000
            details.append(("Percentage", "\(String(format: "%.2f", percent))%"))
        }
        
        return details
    }
    
    private func lightningSendDetails(_ lightningSend: LightningSendFeeStructure) -> [(String, String)] {
        var details: [(String, String)] = []
        
        if lightningSend.minFeeSat > 0 {
            details.append(("Minimum Fee", BitcoinFormatter.shared.formatAmount(lightningSend.minFeeSat)))
        }
        if lightningSend.baseFeeSat > 0 {
            details.append(("Base Fee", BitcoinFormatter.shared.formatAmount(lightningSend.baseFeeSat)))
        }
        
        // Add PPM expiry table
        if !lightningSend.ppmExpiryTable.isEmpty {
            details.append(("", "Percentage by Expiry"))
            let sortedEntries = lightningSend.ppmExpiryTable.sorted(by: { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold })
            
            for (index, entry) in sortedEntries.enumerated() {
                let percent = Double(entry.ppm) / 10_000
                
                if index < sortedEntries.count - 1 {
                    // Not the last entry - show "Below X time"
                    let nextThreshold = sortedEntries[index + 1].expiryBlocksThreshold
                    details.append(("Less than \(blocksToTimeString(UInt32(nextThreshold)))", "\(String(format: "%.2f", percent))%"))
                } else {
                    // Last entry - show "≥X time"
                    details.append(("More than \(blocksToTimeString(UInt32(entry.expiryBlocksThreshold)))", "\(String(format: "%.2f", percent))%"))
                }
            }
        }
        
        return details
    }
}

// MARK: - Fee Card Component

struct FeeCard: View {
    let title: String
    let subtitle: String
    let icon: String?
    let iconBackground: String
    let description: String?
    let details: [(String, String)]
    let isFree: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                ZStack {
                    Image(iconBackground)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                
                Text(title)
                    .font(.title2)
                    .foregroundColor(.primary)
                
                /*
                 Text(subtitle)
                 .font(.body)
                 .foregroundColor(.secondary)
                 */
                
                Spacer()
                
                // Free indicator badge
                if isFree {
                    Text("fee_free")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.Arke.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Arke.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            /*
            // Description (if provided)
            if let description = description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            */
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                ForEach(details.indices, id: \.self) { index in
                    let (label, value) = details[index]
                    
                    if label.isEmpty {
                        // Section header
                        Text(value)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                    } else {
                        HStack {
                            Text(label)
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Show value with free indicator if it's "0.00%" or formatted zero amount
                            if value == "0.00%" || value == BitcoinFormatter.shared.formatAmount(0) {
                                Text("fee_free")
                                    .font(.body)
                                    .foregroundColor(.Arke.green)
                            } else {
                                Text(value)
                                    .font(.body)
                            }
                        }
                    }
                }
                .padding(.leading, 68)
            }
        }
    }
}
