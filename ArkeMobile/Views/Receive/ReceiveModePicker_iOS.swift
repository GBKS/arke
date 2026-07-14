//
//  ReceiveModePicker_iOS.swift
//  Arké
//
//  Created by Assistant on 12/16/25.
//

import SwiftUI
import ArkeUI

/// A floating picker that allows users to switch between Lightning and Payments/Savings balance types
struct ReceiveModePicker_iOS: View {
    @Binding var selectedBalance: ReceiveBalanceType
    let isReadOnlyMode: Bool
    
    var body: some View {
        // Hide in read-only mode (Lightning requires ASP connection)
        if !isReadOnlyMode {
            GlassEffectContainer(spacing: 8.0) {
                HStack(spacing: 0) {
                    Label("receive_request_a_payment", systemImage: "qrcode")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .fontWeight(selectedBalance == .lightning ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(selectedBalance == .lightning ? Color.Arke.gold : .secondary)
                        .animation(nil, value: selectedBalance)
                    
                    Label("receive_share_your_addresses", systemImage: "list.dash")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .fontWeight(selectedBalance == .paymentsAndSavings ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(selectedBalance == .paymentsAndSavings ? Color.Arke.gold : .secondary)
                        .animation(nil, value: selectedBalance)
                }
                .background {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.black.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .frame(width: geometry.size.width / 2 - 4, height: 40)
                            .offset(x: selectedBalance == .paymentsAndSavings ? geometry.size.width / 2 : 4, y: 2)
                            .allowsHitTesting(false)
                    }
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .frame(width: 120)
            .contentShape(Capsule())
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        let newBalance: ReceiveBalanceType = selectedBalance == .lightning ? .paymentsAndSavings : .lightning
                        print("[ReceiveModePicker_iOS] Balance type switching from \(selectedBalance) to \(newBalance)")
                        
                        withAnimation(.smooth(duration: 0.3)) {
                            selectedBalance = newBalance
                        }
                    }
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("balance_type")
            .accessibilityValue(selectedBalance == .lightning ? "Lightning" : "Payments and Savings")
            .accessibilityHint("accessibility_hint_toggle_balance_type")
        }
    }
}
