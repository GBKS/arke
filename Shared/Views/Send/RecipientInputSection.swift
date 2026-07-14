//
//  RecipientInputSection.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/18/25.
//

import SwiftUI
import ArkeUI

struct RecipientInputSection: View {
    @Binding var input: String
    @Binding var state: RecipientState
    @Binding var destination: PaymentDestination?
    let onShowAddressFormats: () -> Void
    let onPaymentRequestParsed: ((PaymentRequest) -> Void)?
    
    @FocusState.Binding var isRecipientFieldFocused: Bool
    
    @State private var debounceTask: Task<Void, Never>?
    @State private var showingAddressReview = false
    @AppStorage(UserDefaults.showAddressIconsKey) private var showAddressIcons = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Text("send_recipient_address")
                    .font(.body)
                    .fontWeight(.medium)
                
                Button(action: onShowAddressFormats) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("action_show_address_formats")
                
                if case .valid = state {
                    Button(action: { showingAddressReview = true }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .help("send_review_address")
                } else if case .bip353Resolved = state {
                    Button(action: { showingAddressReview = true }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .help("send_review_address")
                }
                
                Spacer()
            
                // Validation feedback
                ValidationFeedbackView(state: state)
            }
            
            // Input field
            BitcoinAddressField(
                text: $input,
                placeholder: String(localized: "placeholder_enter_address"),
                isFocused: $isRecipientFieldFocused
            )
            //.frame(maxHeight: 120)
            .onChange(of: input) { _, newValue in
                validateInput(newValue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.arkeSeparatorColor.opacity(0.5), lineWidth: 1)
        )
        .sheet(isPresented: $showingAddressReview) {
            AddressReviewSheet(
                address: input.trimmingCharacters(in: .whitespacesAndNewlines),
                showAddressIcons: showAddressIcons
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func validateInput(_ input: String) {
        // Cancel any pending validation
        debounceTask?.cancel()
        
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            state = .idle
            destination = nil
            return
        }
        
        // Show typing state immediately
        state = .typing
        
        // Debounce the actual validation
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(2000))
            
            guard !Task.isCancelled else { return }
            
            // Check for BIP-353 format first
            if BIP353Resolver.isBIP353Format(trimmed) {
                state = .validBIP353Format
                destination = nil
                return
            }
            
            // Parse non-BIP-353 addresses
            if let paymentRequest = AddressValidator.parsePaymentRequest(trimmed),
               let parsedDestination = paymentRequest.primaryDestination {
                state = .valid
                destination = parsedDestination
                
                // Notify parent about the full payment request so it can decide
                // whether to switch to quick mode for complex requests
                onPaymentRequestParsed?(paymentRequest)
            } else {
                state = .invalid("Invalid address format")
                destination = nil
            }
        }
    }
}
