//
//  OffboardingModalFormView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import ArkeUI
import Bark

struct OffboardingModalFormView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var amountText: String = ""
    let onchainAddress: String
    let maximumAmount: Int?
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void
    
    @FocusState private var isAmountFieldFocused: Bool
    
    private var enteredAmount: Int? {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var isValidAmount: Bool {
        guard let amount = enteredAmount else { return false }
        guard amount > 0 else { return false }
        if let maximum = maximumAmount {
            return amount <= maximum
        }
        return true
    }
    
    private var isFormEnabled: Bool {
        !onchainAddress.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                Image("offboard")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 250)
                    .cornerRadius(25)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel(L10n.buttonClose)
                        .buttonStyle(.bordered)
                        .clipShape(Circle())
                        .padding(.trailing, 8)
                        .padding(.top, 12)
                    }
                
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "button_move_to_savings", defaultValue: "Move to Savings"))
                            .font(.system(.title, design: .serif))
                        
                        Text(String(localized: "balance_transfer_savings_help", defaultValue: "Transfer funds to the savings balance for slower and more expensive payments, with the benefit of no maintenance fees."))
                            .font(.title3)
                            .foregroundColor(.arkeSecondary)
                            .lineSpacing(6)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        /*
                        Text("Amount in satoshis")
                            .font(.headline)
                            .fontWeight(.medium)
                        */
                        
                        TextField(L10n.placeholderEnterAmount, text: $amountText)
                            .textFieldStyle(.plain)
                            .font(.title)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .disabled(!isFormEnabled)
                            .onChange(of: amountText) { oldValue, newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    amountText = filtered
                                }
                            }
                            .focused($isAmountFieldFocused)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button(L10n.buttonDone) {
                                        isAmountFieldFocused = false
                                    }
                                }
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let maximum = maximumAmount {
                                Text(String(localized: "format_maximum", defaultValue: "Maximum: \(BitcoinFormatter.shared.formatAmount(maximum))"))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(localized: "status_loading_balance", defaultValue: "Loading available balance..."))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            
                            FeeEstimateView(input: isValidAmount ? enteredAmount.map { UInt64($0) } : nil) { amountSats in
                                let estimate = try await walletManager.estimateSendToOnchainFee(address: onchainAddress, amountSats: amountSats)
                                return estimate.feeSats
                            }
                        }
                    }
                    
                    Button {
                        if let amount = enteredAmount {
                            onConfirm(amount)
                        }
                    } label: {
                        Text(L10n.buttonStart)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .disabled(!isValidAmount)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding()
        }
    }
}
