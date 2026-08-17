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
    let hasOngoingRefresh: Bool
    let onGoToBalance: (() -> Void)?
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
        hasOngoingRefresh: Bool = false,
        onGoToBalance: (() -> Void)? = nil,
        @ViewBuilder media: () -> Media
    ) {
        self.spendableBalance = spendableBalance
        self.isProcessing = isProcessing
        self.onStartExit = onStartExit
        self.exitCostEstimate = exitCostEstimate
        self.onchainBalance = onchainBalance
        self.isConnectedToServer = isConnectedToServer
        self.hasOngoingRefresh = hasOngoingRefresh
        self.onGoToBalance = onGoToBalance
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
                Text(String(localized: "action_start_forced_move", defaultValue: "Start a forced move", bundle: .module))
                    .font(.system(.title, design: .serif))

                Text(String(localized: "balance_emergency_move_help", defaultValue: "A forced move lets you pull your bitcoin to Savings on your own, without the server.  It’s for emergencies only.", bundle: .module))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
            }
            
            if spendableBalance > 0 {
                // Amount card
                /*
                VStack(spacing: 6) {
                    Text(String(localized: "balance_amount_to_recover", defaultValue: "Amount to move", bundle: .module))
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
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "balance_forced_move_server_connected_title", defaultValue: "Before you start", bundle: .module))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(String(localized: "balance_forced_move_server_connected", defaultValue: "There's a faster, cheaper way to move to Savings in the balance view.", bundle: .module))
                                .font(.body)
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(String(localized: "balance_forced_move_emergencies_only", defaultValue: "Use a forced move only if the server won't cooperate.", bundle: .module))
                                .font(.body)
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let onGoToBalance {
                            Button(action: onGoToBalance) {
                                Text(String(localized: "button_view_balance_details", defaultValue: "View balance", bundle: .module))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.Arke.gold4)
                                    .padding(.horizontal, 4)
                            }
                            .tint(Color.Arke.gold)
                            .buttonStyle(.glassProminent)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.Arke.purple)
                    }
                }
                
                // Ongoing refresh note. Advisory only — a lingering refresh
                // must never block the forced move (exit fails open, see
                // Exit_Refresh_Coordination.md).
                if hasOngoingRefresh {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "balance_forced_move_refresh_in_progress_title", defaultValue: "Refresh in progress", bundle: .module))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(localized: "balance_forced_move_refresh_in_progress", defaultValue: "There’s a pending refresh. If you start a forced move now, it may get cancelled by the refresh. Best to wait.", bundle: .module))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.Arke.purple)
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
                            text: String(localized: "message_takes_24_hours", defaultValue: "A forced move can take 10+ hours", bundle: .module)
                        )
                        
                        CheckableWarningItem(
                            isChecked: $acknowledgedCannotCancel,
                            text: String(localized: "message_cannot_cancel", defaultValue: "It cannot be cancelled", bundle: .module)
                        )
                        
                        CheckableWarningItem(
                            isChecked: $acknowledgedFees,
                            text: String(localized: "balance_final_step_fee", defaultValue: "Fees may be quite large", bundle: .module)
                        )
                        
                        CheckableWarningItem(
                            isChecked: $acknowledgedHourlyCheckin,
                            text: String(localized: "message_hourly_checkin_required", defaultValue: "You will need to check in once per hour until completion", bundle: .module)
                        )
                    }
                    .lineSpacing(6)
                }
                
                // Start button
                Button {
                    onStartExit()
                } label: {
                    if let estimate = exitCostEstimate, !estimate.canAfford {
                        Label(String(localized: "button_insufficient_balance", defaultValue: "Insufficient Balance", bundle: .module), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 21, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    } else {
                        Text(L10n.buttonStart)
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
                Text(String(localized: "balance_no_bitcoin_payments", defaultValue: "You don't have any bitcoin in your payments balance to move.", bundle: .module))
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
    let text: String
    
    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(isChecked ? Color.Arke.green : .primary.opacity(0.15))

                Text(text)
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
    // ScrollView mirrors the real call site (ExitView_iOS); without it the
    // fixed preview height compresses and truncates the text
    ScrollView {
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
            isConnectedToServer: true,
            onGoToBalance: {}
        ) {
            Image("exit")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .padding()
    }
}
#Preview("Cannot Afford") {
    ScrollView {
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
}

#Preview("Ongoing Refresh") {
    ScrollView {
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
            isConnectedToServer: true,
            hasOngoingRefresh: true
        ) {
            Image("exit")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .padding()
    }
}

#Preview("No Estimate") {
    ScrollView {
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
}

