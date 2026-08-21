//
//  BoardingModalFormView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import ArkeUI
import Bark

struct BoardingModalFormView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var amountText: String = ""
    let minimumAmount: Int?
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void
    
    @FocusState private var isAmountFieldFocused: Bool
    
    private var enteredAmount: Int? {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var isValidAmount: Bool {
        guard let amount = enteredAmount, let minimum = minimumAmount else { return false }
        return amount >= minimum
    }
    
    private var isFormEnabled: Bool {
        minimumAmount != nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                Image("board")
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
                        Text(String(localized: "button_move_to_payments", defaultValue: "Move to Payments"))
                            .font(.system(.title, design: .serif))
                        
                        Text(String(localized: "balance_transfer_payments_help", defaultValue: "Transfer funds to the payments balance for fast and low-fee payments, in return for incurring regular maintenance fees."))
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
                                let limited = String(filtered.prefix(15))
                                if limited != newValue {
                                    amountText = limited
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
                            if let minimum = minimumAmount {
                                Text(BitcoinFormatter.shared.formatAmount(minimum) + String(localized: "suffix_minimum", defaultValue: " minimum."))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(localized: "status_loading_minimum", defaultValue: "Loading minimum amount..."))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Always show fee estimate to prevent layout reflow
                            FeeEstimateView(input: isValidAmount ? enteredAmount.map { UInt64($0) } : nil) { amountSats in
                                let estimate = try await walletManager.estimateBoardFee(amountSats: amountSats)
                                return estimate.feeSats
                            }
                            
                            Text(String(localized: "balance_plus_network_fee", defaultValue: "Plus network fee."))
                                .font(.body)
                                .foregroundColor(.secondary)
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
            #if os(iOS)
            // Fallback dismissal for when the keyboard toolbar's Done button fails to appear
            .contentShape(Rectangle())
            .onTapGesture {
                isAmountFieldFocused = false
            }
            #endif
        }
    }
}
