//
//  IncrementalPaymentTestView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/15/25.
//

import SwiftUI
import ArkeUI

/// Test view for sending incremental payments (each payment is 1 sat more than the previous)
struct IncrementalPaymentTestView_iOS: View {
    @Environment(WalletManager.self) private var manager
    
    // Test configuration
    @State private var recipient: String = ""
    @State private var count: String = "10"
    @State private var startAmount: String = "50"
    @State private var delayMs: String = "100"
    
    // Test state
    @State private var isRunning: Bool = false
    @State private var sentCount: Int = 0
    @State private var failedCount: Int = 0
    @State private var currentTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("testing_spam_payments_help")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            
                VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("testing_recipient")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("placeholder_ark_or_lightning_address", text: $recipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isRunning)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("testing_count")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("placeholder_number_of_payments_to_send", text: $count)
                            .keyboardType(.numberPad)
                            .disabled(isRunning)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("testing_start_amount_sats")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("placeholder_initial_payment_amount", text: $startAmount)
                            .keyboardType(.numberPad)
                            .disabled(isRunning)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("testing_delay_ms")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("placeholder_delay_between_payments", text: $delayMs)
                            .keyboardType(.numberPad)
                            .disabled(isRunning)
                    }
                    .padding(.vertical, 4)
                }
                
                if isRunning {
                    VStack(spacing: 12) {
                        HStack {
                            Text("testing_progress")
                            Spacer()
                            Text("\(sentCount)/\(Int(count) ?? 0) sent, \(failedCount) failed")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("testing_stop", role: .destructive) {
                            stopTest()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else {
                    Button("testing_start_test") {
                        startTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(recipient.isEmpty || count.isEmpty || startAmount.isEmpty)
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("nav_title_spam_payments")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func startTest() {
        guard let totalCount = Int(count),
              let baseAmount = Int(startAmount),
              let delay = Int(delayMs) else {
            print("❌ Invalid input parameters")
            return
        }
        
        isRunning = true
        sentCount = 0
        failedCount = 0
        
        currentTask = Task { @MainActor in
            print("🚀 Starting incremental payment test")
            print("   → Recipient: \(recipient)")
            print("   → Count: \(totalCount)")
            print("   → Start amount: \(baseAmount) sats")
            print("   → Delay: \(delay)ms")
            
            for i in 0..<totalCount {
                if Task.isCancelled {
                    print("⏹️ Test cancelled by user")
                    break
                }
                
                let currentAmount = baseAmount + i
                print("📤 Payment \(i+1)/\(totalCount): \(currentAmount) sats")
                
                do {
                    // Parse the payment request
                    guard let paymentRequest = AddressValidator.parsePaymentRequest(recipient),
                          let destination = paymentRequest.primaryDestination else {
                        throw NSError(domain: "TransactionTest", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Invalid payment address"
                        ])
                    }
                    
                    // Execute the payment directly via WalletManager based on format
                    switch destination.format {
                    case .lightningInvoice:
                        _ = try await manager.payLightningInvoice(invoice: destination.address, amountSats: UInt64(currentAmount))
                        
                    case .lightning:
                        _ = try await manager.payLightningAddress(
                            lightningAddress: destination.address,
                            amountSats: UInt64(currentAmount),
                            comment: nil
                        )
                        
                    case .ark:
                        _ = try await manager.send(
                            to: destination.address,
                            amount: currentAmount
                        )
                        
                    default:
                        throw NSError(domain: "TransactionTest", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Unsupported payment format: \(destination.format.displayName)"
                        ])
                    }
                    
                    sentCount += 1
                    print("   ✅ Success (\(sentCount)/\(totalCount))")
                    
                    // Delay before next payment
                    if delay > 0 && i < totalCount - 1 {
                        try? await Task.sleep(for: .milliseconds(delay))
                    }
                    
                } catch {
                    failedCount += 1
                    print("   ❌ Failed: \(error.localizedDescription)")
                    
                    // Stop on first error
                    print("⛔️ Stopping test due to error")
                    break
                }
            }
            
            isRunning = false
            print("🏁 Test completed: \(sentCount) sent, \(failedCount) failed")
        }
    }
    
    private func stopTest() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        print("⏹️ Test stopped by user")
    }
}
