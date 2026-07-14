//
//  ReceiveViewModel.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/3/25.
//

import SwiftUI
import SwiftData
import ArkeUI

/// Shared view model for receive functionality across macOS and iOS
@Observable
@MainActor
final class ReceiveViewModel {
    
    // MARK: - Dependencies
    
    private let walletManager: WalletManager
    private let modelContext: ModelContext?
    
    // MARK: - State
    
    var selectedBalance: ReceiveBalanceType = .lightning
    var showingQRCode = false
    var showingAmountAndNote = false
    var amount = ""
    var note = ""
    
    // Lightning-specific state
    var lightningInvoice: String?
    var isGeneratingInvoice = false
    var invoiceError: String?
    var showCopySuccess = false
    var showAddressesOnly = false
    
    // MARK: - Initialization
    
    init(walletManager: WalletManager, modelContext: ModelContext? = nil) {
        self.walletManager = walletManager
        self.modelContext = modelContext
    }
    
    // MARK: - Computed Properties
    
    var balanceTypeLabel: String {
        switch selectedBalance {
        case .payments: return String(localized: "receive_balance_payments")
        case .savings: return String(localized: "receive_balance_savings")
        case .lightning: return String(localized: "network_lightning")
        case .paymentsAndSavings: return String(localized: "receive_payments_and_savings")
        }
    }
    
    var hasQRContent: Bool {
        getCurrentQRContent() != nil
    }
    
    /// Gets the user's profile name for use in BIP21 URI labels
    private var userProfileName: String? {
        guard let modelContext = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        
        let trimmedName = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmedName.isEmpty ? nil : trimmedName
    }
    
    // MARK: - Public Methods
    
    /// Changes the selected balance type and clears state as needed
    func changeBalanceType(to newType: ReceiveBalanceType) {
        let oldType = selectedBalance
        selectedBalance = newType
        
        // Clear Lightning state when switching balance types
        clearLightningInvoice()
        
        // Clear amount and note when switching to/from Lightning
        // since Lightning has different requirements
        if (oldType == .lightning) != (newType == .lightning) {
            amount = ""
            note = ""
            showingAmountAndNote = false
        }
    }
    
    /// Proceeds with or without generating a Lightning invoice based on amount
    func proceedWithOrWithoutInvoice() async {
        // If amount is valid and > 0, generate invoice
        if let amountSats = BitcoinFormatter.shared.parseUserInput(amount), amountSats > 0 {
            await generateLightningInvoice()
        } else {
            // No amount or invalid - show addresses only
            withAnimation(.easeInOut(duration: 0.3)) {
                showAddressesOnly = true
            }
        }
    }
    
    /// Generates a Lightning invoice for the current amount
    func generateLightningInvoice() async {
        // Parse user input to satoshis using the formatter
        guard let amountSats = BitcoinFormatter.shared.parseUserInput(amount), amountSats > 0 else {
            invoiceError = "Please enter a valid amount greater than 0"
            return
        }

        // Convert to UInt64 for API
        guard let amountInt = UInt64(exactly: amountSats) else {
            invoiceError = "Amount is invalid"
            return
        }

        // Add reasonable limits for Lightning invoices
        guard amountInt <= 10_000_000 else { // 0.1 BTC limit
            invoiceError = "Amount too large. Maximum is 10,000,000 sats"
            return
        }
        
        isGeneratingInvoice = true
        invoiceError = nil
        
        do {
            let invoice = try await walletManager.getLightningInvoice(amountSats: amountInt, description: nil)
            try await walletManager.sync()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.lightningInvoice = invoice
            }
            self.isGeneratingInvoice = false
        } catch {
            self.invoiceError = "Failed to generate invoice: \(error.localizedDescription)"
            self.isGeneratingInvoice = false
        }
    }
    
    /// Clears the Lightning invoice and related state
    func clearLightningInvoice() {
        lightningInvoice = nil
        invoiceError = nil
        showCopySuccess = false
    }
    
    /// Resets the entire Lightning form (invoice + amount + note)
    func resetLightningForm() {
        lightningInvoice = nil
        invoiceError = nil
        showCopySuccess = false
        showAddressesOnly = false
        amount = ""
        note = ""
    }
    
    /// Copies text to clipboard and shows success feedback
    func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        
        // Show success feedback
        withAnimation {
            showCopySuccess = true
        }
        
        // Hide success feedback after 2 seconds
        Task {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    showCopySuccess = false
                }
            }
        }
    }
    
    /// Extracts the invoice string from JSON or returns the input if it's plain text
    func extractInvoiceFromJSON(_ input: String) -> String {
        // First, try to parse as JSON
        if let data = input.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let invoice = json["invoice"] as? String {
                    return invoice
                }
            } catch {
                // If JSON parsing fails, treat as plain string
                print("Failed to parse Lightning invoice as JSON, using as plain string: \(error)")
            }
        }
        
        // If not JSON or parsing failed, return the original string
        return input
    }
    
    /// Gets the current QR code content and title based on selected balance type
    func getCurrentQRContent() -> (content: String, title: String)? {
        // For Lightning, use the generated invoice (extract from JSON if needed)
        if selectedBalance == .lightning {
            guard let rawInvoice = lightningInvoice else { return nil }
            let actualInvoice = extractInvoiceFromJSON(rawInvoice)
            return (content: actualInvoice, title: "Lightning Invoice")
        }
        
        return ReceiveQRContentHelper.getCurrentQRContent(
            selectedBalance: selectedBalance,
            amount: amount,
            note: note,
            arkAddress: walletManager.arkAddress,
            onchainAddress: walletManager.onchainAddress,
            label: userProfileName
        )
    }
    
    /// Gets the share content based on selected balance type
    func getShareContent() -> String? {
        // For Lightning, use the generated invoice (extract from JSON if needed)
        if selectedBalance == .lightning {
            guard let rawInvoice = lightningInvoice else { return nil }
            return extractInvoiceFromJSON(rawInvoice)
        }
        
        return ReceiveQRContentHelper.getShareContent(
            selectedBalance: selectedBalance,
            amount: amount,
            note: note,
            arkAddress: walletManager.arkAddress,
            onchainAddress: walletManager.onchainAddress,
            label: userProfileName
        )
    }
    
    /// Checks if user has a configured profile (name and optionally avatar)
    var hasUserProfile: Bool {
        guard let modelContext = modelContext else { return false }
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? modelContext.fetch(descriptor).first else { return false }
        return profile.isConfigured
    }
    
    /// Gets vCard data for sharing user profile with Bitcoin payment info
    func getVCardData() -> URL? {
        guard let shareContent = getShareContent() else { return nil }
        guard let modelContext = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? modelContext.fetch(descriptor).first,
              let userName = userProfileName,
              !userName.isEmpty else {
            return nil
        }
        
        // Generate vCard
        guard let vcardData = VCardGenerator.generateVCard(
            name: userName,
            bitcoinURI: shareContent,
            avatarData: profile.avatarData,
            note: "Bitcoin payment address"
        ) else {
            return nil
        }
        
        // Create a temporary file URL for the vCard
        let tempDir = FileManager.default.temporaryDirectory
        let vcardURL = tempDir.appendingPathComponent("\(userName).vcf")
        
        do {
            try vcardData.write(to: vcardURL)
            return vcardURL
        } catch {
            print("Failed to write vCard to temp file: \(error)")
            return nil
        }
    }
    
    // MARK: - Sheet Management
    
    func showQRCode() {
        showingQRCode = true
    }
    
    func hideQRCode() {
        showingQRCode = false
    }
    
    func toggleAmountAndNote() {
        showingAmountAndNote.toggle()
    }
}
