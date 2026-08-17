//
//  BalanceInfoSheet.swift
//  Arké
//
//  Created by Christoph on 2/5/26.
//

import SwiftUI
import ArkeUI

struct BalanceInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(String(localized: "balance_about_title", defaultValue: "About Your Balances"))
                        .font(.system(size: 30, design: .serif))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                
                    // Payments Balance Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image("wallet")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                            
                            Text(String(localized: "balance_payments", defaultValue: "Payments Balance"))
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        Text(String(localized: "balance_payments_help", defaultValue: "Your Payments Balance uses the Ark protocol to enable fast, low-fee Bitcoin payments similar to Lightning."))
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            BalanceInfoSheetRow(icon: "hare", text: String(localized: "balance_payments_fast", defaultValue: "Super-fast payments"))
                            BalanceInfoSheetRow(icon: "bitcoinsign", text: String(localized: "balance_payments_low_fees", defaultValue: "Low transaction fees"))
                            BalanceInfoSheetRow(icon: "calendar", text: String(localized: "balance_payments_periodic_fees", defaultValue: "Periodic maintenance fees"))
                            BalanceInfoSheetRow(icon: "network", text: String(localized: "balance_payments_ark_server", defaultValue: "Facilitated by an Ark server"))
                        }
                    }
                    
                    Divider()
                    
                    // Savings Balance Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image("safe")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                            
                            Text(String(localized: "balance_savings", defaultValue: "Savings Balance"))
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        Text(String(localized: "balance_savings_help", defaultValue: "Your Savings Balance is standard Bitcoin held directly on the blockchain with full security."))
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            BalanceInfoSheetRow(icon: "tortoise.fill", text: String(localized: "balance_savings_slow", defaultValue: "Slow payments (10+ minutes)"))
                            BalanceInfoSheetRow(icon: "bitcoinsign", text: String(localized: "balance_savings_high_fees", defaultValue: "High transaction fees"))
                            BalanceInfoSheetRow(icon: "checkmark.circle.fill", text: String(localized: "balance_savings_no_fees", defaultValue: "No maintenance fees"))
                            BalanceInfoSheetRow(icon: "network", text: String(localized: "balance_savings_bitcoin_network", defaultValue: "Uses the Bitcoin Network"))
                        }
                    }
                    
                    Divider()
                    
                    // Moving Funds Section
                    VStack(alignment: .leading, spacing: 12) {
                        /*
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.arkeGold)
                            
                            Text("Moving Between Balances")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        */
                        
                        Text(String(localized: "balance_arrows_help", defaultValue: "Use the arrows between your balances to move funds."))
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            BalanceInfoSheetRow(icon: "arrow.up.circle.fill", text: String(localized: "balance_transfer_savings_to_payments", defaultValue: "From Savings to Payments"))
                            BalanceInfoSheetRow(icon: "arrow.down.circle.fill", text: String(localized: "balance_transfer_payments_to_savings", defaultValue: "From Payments to Savings"))
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.buttonDone) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BalanceInfoSheetRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.Arke.gold)
                .frame(width: 20)
            
            Text(text)
                .font(.body)
        }
    }
}
