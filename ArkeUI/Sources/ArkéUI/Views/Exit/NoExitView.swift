//
//  NoExitView.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

import SwiftUI

public struct NoExitView<Media: View>: View {
    let spendableBalance: UInt64
    let isProcessing: Bool
    let onStartExit: () -> Void
    let exitCostEstimate: ExitCostEstimate?
    let onchainBalance: UInt64
    let isConnectedToServer: Bool
    let media: Media

    @State private var acknowledgedTakesTime = false
    @State private var acknowledgedCannotCancel = false
    @State private var acknowledgedFees = false
    @State private var acknowledgedHourlyCheckin = false

    public init(
        spendableBalance: UInt64,
        isProcessing: Bool,
        onStartExit: @escaping () -> Void,
        exitCostEstimate: ExitCostEstimate?,
        onchainBalance: UInt64,
        isConnectedToServer: Bool,
        @ViewBuilder media: () -> Media
    ) {
        self.spendableBalance = spendableBalance
        self.isProcessing = isProcessing
        self.onStartExit = onStartExit
        self.exitCostEstimate = exitCostEstimate
        self.onchainBalance = onchainBalance
        self.isConnectedToServer = isConnectedToServer
        self.media = media()
    }
    
    private var allAcknowledged: Bool {
        acknowledgedTakesTime && acknowledgedCannotCancel && acknowledgedFees && acknowledgedHourlyCheckin
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            media
                .frame(maxWidth: .infinity, maxHeight: 300)
                .cornerRadius(25)
                .clipped()
            
            // Icon and title
            VStack(alignment: .leading, spacing: 10) {
                Text("action_start_forced_move", bundle: .module)
                    .font(.system(.title, design: .serif))

                Text(String(localized: "balance_emergency_move_help", bundle: .module))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
            }
            
            if spendableBalance > 0 {
                // Amount card
                /*
                VStack(spacing: 6) {
                    Text("balance_amount_to_recover")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(BitcoinFormatter.shared.formatAmount(spendableBalance))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                */
                
                // Connection status info box
                if isConnectedToServer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("balance_forced_move_server_connected", bundle: .module)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("balance_forced_move_emergencies_only", bundle: .module)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                    }
                }
                
                // Exit cost estimate card (if available)
                if let estimate = exitCostEstimate {
                    ExitCostEstimateCard(
                        spendableBalance: spendableBalance,
                        estimate: estimate,
                        onchainBalance: onchainBalance
                    )
                }
                
                
                
                // Icon and title
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        CheckableWarningItem(
                            isChecked: $acknowledgedTakesTime,
                            text: "message_takes_24_hours"
                        )
                        
                        CheckableWarningItem(
                            isChecked: $acknowledgedCannotCancel,
                            text: "message_cannot_cancel"
                        )
                        
                        CheckableWarningItem(
                            isChecked: $acknowledgedFees,
                            text: "balance_final_step_fee"
                        )
                        
                        CheckableWarningItem(
                            isChecked: $acknowledgedHourlyCheckin,
                            text: "message_hourly_checkin_required"
                        )
                    }
                    .lineSpacing(6)
                }
                
                // Start button
                Button {
                    onStartExit()
                } label: {
                    if let estimate = exitCostEstimate, !estimate.canAfford {
                        Label(String(localized: "button_insufficient_balance", bundle: .module), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 21, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    } else {
                        Text("button_start", bundle: .module)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(exitCostEstimate?.canAfford == false ? .red : Color.Arke.gold)
                .disabled(spendableBalance == 0 || isProcessing || (exitCostEstimate?.canAfford == false) || !allAcknowledged)
            } else {
                Text(String(localized: "balance_no_bitcoin_payments", bundle: .module))
                    .font(.title3)
                    .foregroundColor(.primary)
                    .padding(.top, 10)
            }
            
            Spacer()
        }
    }
}

struct CheckableWarningItem: View {
    @Binding var isChecked: Bool
    let text: LocalizedStringKey
    
    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(isChecked ? Color.Arke.green : .primary.opacity(0.15))

                Text(text, bundle: .module)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ExitCostRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(color)
        }
    }
}

// MARK: - Supporting Types

public struct ExitCostEstimate {
    public let lowCost: UInt64      // Optimistic scenario
    public let totalCost: UInt64    // Mid-point estimate
    public let highCost: UInt64     // Conservative scenario
    public let minTransactions: Int // Optimistic transaction count
    public let maxTransactions: Int // Conservative transaction count
    let feeRate: UInt64
    public let canAfford: Bool
    public let onchainBalance: UInt64

    public init(
        lowCost: UInt64,
        totalCost: UInt64,
        highCost: UInt64,
        minTransactions: Int,
        maxTransactions: Int,
        feeRate: UInt64,
        canAfford: Bool,
        onchainBalance: UInt64
    ) {
        self.lowCost = lowCost
        self.totalCost = totalCost
        self.highCost = highCost
        self.minTransactions = minTransactions
        self.maxTransactions = maxTransactions
        self.feeRate = feeRate
        self.canAfford = canAfford
        self.onchainBalance = onchainBalance
    }

    public var shortfall: UInt64 {
        canAfford ? 0 : highCost - onchainBalance
    }

    public var isRange: Bool {
        lowCost != highCost
    }

    public var transactionRange: String {
        if minTransactions == maxTransactions {
            return "\(minTransactions)"
        } else {
            return "\(minTransactions) – \(maxTransactions)"
        }
    }
}

// MARK: - Previews

#Preview("Can Afford") {
    NoExitView(
        spendableBalance: 100000,
        isProcessing: false,
        onStartExit: {},
        exitCostEstimate: ExitCostEstimate(
            lowCost: 12000,
            totalCost: 15000,
            highCost: 18000,
            minTransactions: 4,
            maxTransactions: 7,
            feeRate: 8,
            canAfford: true,
            onchainBalance: 50000
        ),
        onchainBalance: 50000,
        isConnectedToServer: true
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}
#Preview("Cannot Afford") {
    NoExitView(
        spendableBalance: 100000,
        isProcessing: false,
        onStartExit: {},
        exitCostEstimate: ExitCostEstimate(
            lowCost: 12000,
            totalCost: 15000,
            highCost: 18000,
            minTransactions: 4,
            maxTransactions: 7,
            feeRate: 8,
            canAfford: false,
            onchainBalance: 10000
        ),
        onchainBalance: 10000,
        isConnectedToServer: false
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}

#Preview("No Estimate") {
    NoExitView(
        spendableBalance: 100000,
        isProcessing: false,
        onStartExit: {},
        exitCostEstimate: nil,
        onchainBalance: 10000,
        isConnectedToServer: true
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}

