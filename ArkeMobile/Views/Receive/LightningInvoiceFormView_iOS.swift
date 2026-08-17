//
//  LightningInvoiceFormView.swift
//  Arké
//
//  Created by Assistant on 1/28/26.
//

import SwiftUI
import ArkeUI

/// Fluent Lightning invoice creation form with numeric keypad and optional note
struct LightningInvoiceFormView_iOS: View {
    @Binding var amount: String
    @Binding var note: String
    @State private var showNoteField = false
    @FocusState private var isNoteFocused: Bool
    @State private var gradientPhase: CGFloat = 0
    
    let onGenerateInvoice: () -> Void
    
    private var formattedAmount: String {
        // If user is typing a partial decimal (e.g., "0.", "0.00"), show the raw input with symbol
        if BitcoinFormatter.shared.allowsDecimalInput && amount.contains(".") {
            return BitcoinFormatter.shared.formatPartialDecimalInput(amount)
        }
        
        // Otherwise, parse and format the complete value
        guard let sats = BitcoinFormatter.shared.parseUserInput(amount) else {
            return BitcoinFormatter.shared.formatAmount(0)
        }
        return BitcoinFormatter.shared.formatAmount(sats)
    }
    
    /// Dynamic font size that shrinks as text gets longer
    private var dynamicFontSize: CGFloat {
        let baseSize: CGFloat = 56
        let threshold = 6
        let length = formattedAmount.count
        
        if length <= threshold {
            return baseSize
        }
        
        // Reduce by 1 point for each character beyond threshold
        let reduction = CGFloat(length - threshold)
        return max(baseSize - reduction*1.5, 20) // Minimum size of 20 to keep it readable
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Amount display area - fills available space
            VStack(spacing: 16) {
                Text(formattedAmount)
                    .font(.system(size: dynamicFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.Arke.gold.opacity(amount.isEmpty ? 0.5 : 1.0))
                    .frame(height: 56) // Fixed height to prevent layout shifts
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: formattedAmount)
                
                // Optional note toggle/field
                if showNoteField {
                    TextField(String(localized: "placeholder_note_optional", defaultValue: "Add note (optional)"), text: $note)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNoteFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showNoteField = false
                                isNoteFocused = false
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !note.isEmpty {
                    // Show entered note as tappable text
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNoteField = true
                            isNoteFocused = true
                        }
                    } label: {
                        Text(note)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.horizontal, 40)
                } else {
                    // Show "+ Add note" button when empty
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNoteField = true
                            isNoteFocused = true
                        }
                    } label: {
                        Text(String(localized: "receive_add_note", defaultValue: "Add note"))
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            
            Spacer()
                .frame(minHeight: 0)
            
            // Keypad at bottom (hidden when note field is active)
            if !showNoteField {
                CustomNumericKeypad_iOS(
                    amount: $amount,
                    onConfirm: {
                        onGenerateInvoice()
                    },
                    theme: .textured(imageName: "black-marble"),
                    showPeriod: BitcoinFormatter.shared.allowsDecimalInput,
                    validateInput: { newAmount in
                        // Validate that amount doesn't exceed limits
                        guard let sats = BitcoinFormatter.shared.parseUserInput(newAmount) else {
                            return true // Allow partial input while typing
                        }
                        // Lightning invoice limit: max 1 BTC (100,000,000 sats)
                        return sats <= 100_000_000
                    },
                    allowEmptyConfirm: true
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: showNoteField)
    }
}
