//
//  InvoiceGenerationTestView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/15/25.
//

import SwiftUI
import ArkeUI
import UIKit
import OSLog

/// Test view for generating multiple Lightning invoices and copying them to clipboard
struct InvoiceGenerationTestView_iOS: View {
    @Environment(WalletManager.self) private var manager
    
    /// Logger for invoice generation test operations
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "InvoiceGenerationTest")
    
    // Test configuration
    @State private var count: String = "5"
    @State private var amount: String = "100"
    
    // Test state
    @State private var isRunning: Bool = false
    @State private var generatedCount: Int = 0
    @State private var failedCount: Int = 0
    @State private var currentTask: Task<Void, Never>?
    @State private var invoices: [String] = []
    @State private var showCopiedAlert: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("testing_invoice_generation_help")
                    .font(.body)
                    .foregroundColor(.secondary)
            
                VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("testing_count")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("placeholder_number_of_invoices_to_generate", text: $count)
                            .keyboardType(.numberPad)
                            .disabled(isRunning)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("testing_amount_sats")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("placeholder_invoice_amount", text: $amount)
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
                            Text("\(generatedCount)/\(Int(count) ?? 0) generated, \(failedCount) failed")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("testing_stop", role: .destructive) {
                            stopTest()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else if !invoices.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Text("testing_results")
                            Spacer()
                            Text("\(invoices.count) invoices generated")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("testing_copy_all_to_clipboard") {
                            copyInvoicesToClipboard()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("testing_clear_results") {
                            clearResults()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("testing_generate_invoices") {
                        startTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(count.isEmpty || amount.isEmpty)
                }
            
                if !invoices.isEmpty {
                    ForEach(Array(invoices.enumerated()), id: \.offset) { index, invoice in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Invoice #\(index + 1)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(invoice)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = invoice
                                showCopiedAlert = true
                            }) {
                                Label("testing_copy_invoice", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("nav_title_invoice_generation")
        .navigationBarTitleDisplayMode(.large)
        .alert("status_copied_exclaim", isPresented: $showCopiedAlert) {
            Button("button_ok", role: .cancel) { }
        } message: {
            Text(invoices.count > 1 ? LocalizedStringKey("testing_all_invoices_copied_to_clipboard") : LocalizedStringKey("testing_invoice_copied_to_clipboard"))
        }
    }
    
    private func startTest() {
        guard let totalCount = Int(count),
              let invoiceAmount = UInt64(amount) else {
            Self.logger.error("Invalid input parameters")
            return
        }
        
        isRunning = true
        generatedCount = 0
        failedCount = 0
        invoices = []
        
        currentTask = Task { @MainActor in
            Self.logger.info("Starting invoice generation test - Count: \(totalCount), Amount: \(invoiceAmount) sats")
            
            for i in 0..<totalCount {
                if Task.isCancelled {
                    Self.logger.info("Test cancelled by user")
                    break
                }
                
                // Increment amount by 1 sat for each invoice
                let currentAmount = invoiceAmount + UInt64(i)
                Self.logger.debug("Generating invoice \(i+1)/\(totalCount) for \(currentAmount) sats")
                
                do {
                    let invoice = try await manager.getLightningInvoice(amountSats: currentAmount, description: nil)
                    invoices.append(invoice)
                    generatedCount += 1
                    Self.logger.info("Invoice generation success (\(generatedCount)/\(totalCount))")
                    
                } catch {
                    failedCount += 1
                    Self.logger.error("Invoice generation failed: \(error.localizedDescription)")
                    
                    // Continue on error instead of stopping
                }
            }
            
            isRunning = false
            Self.logger.info("Test completed: \(generatedCount) generated, \(failedCount) failed")
        }
    }
    
    private func stopTest() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        Self.logger.info("Test stopped by user")
    }
    
    private func copyInvoicesToClipboard() {
        let allInvoices = invoices.joined(separator: "\n")
        UIPasteboard.general.string = allInvoices
        showCopiedAlert = true
        Self.logger.info("Copied \(invoices.count) invoices to clipboard")
    }
    
    private func clearResults() {
        invoices = []
        generatedCount = 0
        failedCount = 0
        Self.logger.debug("Results cleared")
    }
}
