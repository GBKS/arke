//
//  TransactionClaimExitBanner.swift
//  Arké
//
//  Created by Assistant on 2/6/26.
//

import SwiftUI
import ArkeUI

/// Banner displayed when a unilateral exit transaction has claimable VTXOs.
/// Allows the user to finalize the withdrawal by claiming the exits to their onchain wallet.
/// Also shows progress state after claim has been submitted.
struct TransactionClaimExitBanner: View {
    let hasClaimableExit: Bool
    let hasClaimInProgress: Bool
    let hasClaimComplete: Bool
    let claimableAmount: UInt64
    let estimatedFee: UInt64?
    let isCalculatingFee: Bool
    let isClaiming: Bool
    let onClaim: () -> Void
    
    @State private var showClaimConfirmation = false
    
    var body: some View {
        if hasClaimableExit || hasClaimInProgress || hasClaimComplete {
            VStack(spacing: 0) {
                if hasClaimComplete {
                    // Complete state - claim has been confirmed
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                        
                        Text(String(localized: "status_withdrawal_complete", bundle: .module))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.Arke.green)
                    .cornerRadius(16)
                } else if hasClaimInProgress {
                    // Progress state - claim has been submitted
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        
                        Text(String(localized: "status_withdrawal_progress", bundle: .module))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.Arke.blue)
                    .cornerRadius(16)
                } else {
                    // Claimable state - ready to claim
                    VStack(alignment: .leading, spacing: 12) {
                        // Title
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                            
                            Text(String(localized: "status_ready_finalize", bundle: .module))
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        // Amount and fee info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "label_amount_colon", bundle: .module))
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text(formattedClaimableAmount)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text(String(localized: "label_fee_colon", bundle: .module))
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                
                                if isCalculatingFee {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                } else if let fee = estimatedFee {
                                    Text(BitcoinFormatter.shared.formatAmount(Int(fee)))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                } else {
                                    Text(String(localized: "status_calculating", bundle: .module))
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        
                        // Action button
                        Button(action: {
                            showClaimConfirmation = true
                        }) {
                            HStack {
                                if isClaiming {
                                    ProgressView()
                                        .tint(.Arke.blue)
                                    Text(String(localized: "status_finalizing", bundle: .module))
                                } else {
                                    Text(String(localized: "button_finalize_claim", bundle: .module))
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.Arke.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isClaiming || isCalculatingFee)
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color.Arke.blue)
                    .cornerRadius(16)
                }
            }
            .alert(String(localized: "button_finalize_withdrawal", bundle: .module), isPresented: $showClaimConfirmation) {
                Button(String(localized: "button_cancel", bundle: .module), role: .cancel) { }
                Button(String(localized: "button_finalize", bundle: .module)) {
                    onClaim()
                }
            } message: {
                if let fee = estimatedFee {
                    Text(String(localized: "Withdraw \(formattedClaimableAmount) to your savings balance?\n\nFee: \(BitcoinFormatter.shared.formatAmount(Int(fee)))", bundle: .module))
                } else {
                    Text(String(localized: "balance_confirm_withdraw", defaultValue: "Withdraw \(formattedClaimableAmount) to your savings balance?", bundle: .module))
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedClaimableAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(claimableAmount))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        TransactionClaimExitBanner(
            hasClaimableExit: true,
            hasClaimInProgress: false,
            hasClaimComplete: false,
            claimableAmount: 150000,
            estimatedFee: 1500,
            isCalculatingFee: false,
            isClaiming: false,
            onClaim: {
                print("Claim tapped")
            }
        )
        
        Text("With calculated fee")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}

#Preview("Calculating Fee") {
    VStack(spacing: 20) {
        TransactionClaimExitBanner(
            hasClaimableExit: true,
            hasClaimInProgress: false,
            hasClaimComplete: false,
            claimableAmount: 100000,
            estimatedFee: nil,
            isCalculatingFee: true,
            isClaiming: false,
            onClaim: {
                print("Claim tapped")
            }
        )
        
        Text("Calculating fee state")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}

#Preview("Claiming") {
    VStack(spacing: 20) {
        TransactionClaimExitBanner(
            hasClaimableExit: true,
            hasClaimInProgress: false,
            hasClaimComplete: false,
            claimableAmount: 100000,
            estimatedFee: 1500,
            isCalculatingFee: false,
            isClaiming: true,
            onClaim: {
                print("Claim tapped")
            }
        )
        
        Text("Claiming in progress")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}

#Preview("Claim In Progress") {
    VStack(spacing: 20) {
        TransactionClaimExitBanner(
            hasClaimableExit: false,
            hasClaimInProgress: true,
            hasClaimComplete: false,
            claimableAmount: 100000,
            estimatedFee: 1500,
            isCalculatingFee: false,
            isClaiming: false,
            onClaim: {
                print("Claim tapped")
            }
        )
        
        Text("After claim broadcast")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}

#Preview("Claim Complete") {
    VStack(spacing: 20) {
        TransactionClaimExitBanner(
            hasClaimableExit: false,
            hasClaimInProgress: false,
            hasClaimComplete: true,
            claimableAmount: 100000,
            estimatedFee: 1500,
            isCalculatingFee: false,
            isClaiming: false,
            onClaim: {
                print("Claim tapped")
            }
        )
        
        Text("After claim confirmed")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}

