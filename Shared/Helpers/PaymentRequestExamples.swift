//
//  PaymentRequestExamples.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//
//  Examples demonstrating the new PaymentRequest API

import Foundation
import ArkeUI

/// Examples of using the refactored AddressValidator with PaymentRequest
enum PaymentRequestExamples {
    
    // MARK: - Simple Address Parsing
    
    static func parseSimpleBitcoinAddress() {
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        if let request = AddressValidator.parsePaymentRequest(address) {
            print("✅ Parsed Bitcoin address")
            print("   Format: \(request.primaryFormat?.displayName ?? "Unknown")")
            print("   Network: \(request.primaryNetwork?.displayName ?? "Unknown")")
            print("   Address: \(request.primaryAddress ?? "")")
            print("   Destinations: \(request.destinations.count)")
        }
    }
    
    static func parseLightningInvoice() {
        let invoice = "lnbc100n1..."
        
        if let request = AddressValidator.parsePaymentRequest(invoice) {
            print("✅ Parsed Lightning invoice")
            if let amount = request.amount {
                print("   Amount: \(amount) sats")
            }
            print("   Has alternatives: \(request.hasAlternatives)")
        }
    }
    
    // MARK: - BIP-21 URI with Multiple Destinations
    
    static func parseUnifiedBIP21URI() {
        // Example: BIP-21 URI with Bitcoin, Ark, and Lightning
        let uri = """
        bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?\
        amount=0.001&\
        label=Coffee%20Payment&\
        message=Thanks%20for%20the%20coffee&\
        ark=ark1qwertyuiop&\
        lightning=lnbc100n1...
        """
        
        if let request = AddressValidator.parsePaymentRequest(uri) {
            print("✅ Parsed unified BIP-21 URI")
            print("   Amount: \(request.amount ?? 0) sats")
            print("   Label: \(request.label ?? "N/A")")
            print("   Message: \(request.message ?? "N/A")")
            print("   Total destinations: \(request.destinations.count)")
            print("")
            
            // Primary destination (Bitcoin address from URI path)
            if let primary = request.primaryDestination {
                print("   Primary: \(primary.format.displayName)")
                print("     → \(primary.shortAddress)")
            }
            
            // Alternative destinations
            if request.hasAlternatives {
                print("")
                print("   Alternatives:")
                for alt in request.alternativeDestinations {
                    print("     • \(alt.format.displayName)")
                    print("       → \(alt.shortAddress)")
                }
            }
        }
    }
    
    // MARK: - Querying by Format
    
    static func queryByFormat() {
        let uri = "bitcoin:bc1q...?ark=ark1...&lightning=lnbc..."
        
        guard let request = AddressValidator.parsePaymentRequest(uri) else { return }
        
        // Check if request supports specific formats
        if request.supports(.ark) {
            print("✅ Supports Ark payments")
            if let arkDest = request.firstDestination(for: .ark) {
                print("   Ark address: \(arkDest.address)")
            }
        }
        
        if request.supports(.lightningInvoice) {
            print("✅ Supports Lightning payments")
            if let lnDest = request.firstDestination(for: .lightningInvoice) {
                print("   Lightning invoice: \(lnDest.shortAddress)")
            }
        }
        
        // Get all destinations of a specific format
        let bitcoinDestinations = request.destinations(for: .bitcoin)
        print("Found \(bitcoinDestinations.count) Bitcoin destination(s)")
    }
    
    // MARK: - Network Filtering
    
    static func filterByNetwork() {
        let testnetAddress = "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Parse with network validation
        if let request = AddressValidator.parsePaymentRequest(
            testnetAddress,
            expectedNetwork: .testnet
        ) {
            print("✅ Valid for testnet")
            print("   Matching destinations: \(request.destinations.count)")
        } else {
            print("❌ Not valid for testnet")
        }
    }
    
    static func filterMultiDestinationByNetwork() {
        let uri = "bitcoin:bc1q...?ark=t..." // Mainnet Bitcoin + Signet Ark
        
        guard let request = AddressValidator.parsePaymentRequest(uri) else { return }
        
        // Filter to only mainnet destinations
        if let mainnetOnly = request.filtered(for: .mainnet) {
            print("✅ Mainnet destinations: \(mainnetOnly.destinations.count)")
        }
        
        // Filter to only signet destinations
        if let signetOnly = request.filtered(for: .signet) {
            print("✅ Signet destinations: \(signetOnly.destinations.count)")
        }
    }
    
    // MARK: - Creating BIP-21 URIs
    
    static func createUnifiedBIP21URI() {
        // Create a unified payment request
        let uri = BIP21URIHelper.createBIP21URI(
            arkAddress: "ark1qwertyuiop",
            onchainAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            lightningInvoice: "lnbc100n1...",
            amountSats: "100000",
            label: "Coffee Payment",
            message: "Thanks!"
        )
        
        print("✅ Created unified BIP-21 URI:")
        print(uri)
    }
    
    static func createFromPaymentRequest() {
        // Parse an existing payment request
        let originalURI = "bitcoin:bc1q...?ark=ark1...&amount=0.001"
        
        guard let request = AddressValidator.parsePaymentRequest(originalURI) else { return }
        
        // Convert back to BIP-21 URI
        let newURI = BIP21URIHelper.createBIP21URI(from: request)
        
        print("✅ Round-trip conversion:")
        print("   Original: \(originalURI)")
        print("   New:      \(newURI)")
    }
    
    // MARK: - Integration with Contact System
    
    static func addContactAddress() async {
        let contactService = ContactAddressService(taskManager: TaskDeduplicationManager())
        let contactId = UUID()
        
        // Parse a BIP-21 URI with multiple destinations
        let uri = "bitcoin:bc1q...?ark=ark1..."
        
        do {
            // This will extract the primary destination and create a contact address
            let contactAddress = try await contactService.validateAndCreateAddress(
                uri,
                for: contactId,
                label: "Coffee Shop",
                isPrimary: true
            )
            
            print("✅ Created contact address: \(contactAddress.displayName)")
        } catch {
            print("❌ Failed to create contact address: \(error)")
        }
    }
    
    // MARK: - UI Integration Examples
    
    static func displayPaymentOptions() {
        let uri = "bitcoin:bc1q...?ark=ark1...&lightning=lnbc..."
        
        guard let request = AddressValidator.parsePaymentRequest(uri) else { return }
        
        print("💳 Payment Options:")
        print("")
        
        // Show all available payment methods
        for (index, destination) in request.destinations.enumerated() {
            let isPrimary = index == 0
            let prefix = isPrimary ? "⭐️" : "  "
            
            print("\(prefix) \(destination.displayName)")
            print("   \(destination.address)")
            
            if isPrimary, let amount = request.amount {
                print("   Amount: \(amount) sats")
            }
            print("")
        }
        
        if let label = request.label {
            print("📝 Label: \(label)")
        }
        
        if let message = request.message {
            print("💬 Message: \(message)")
        }
    }
    
    // MARK: - Run All Examples
    
    static func runAllExamples() async {
        print("=== PaymentRequest API Examples ===\n")
        
        print("1. Simple Bitcoin Address")
        parseSimpleBitcoinAddress()
        print("")
        
        print("2. Lightning Invoice")
        parseLightningInvoice()
        print("")
        
        print("3. Unified BIP-21 URI")
        parseUnifiedBIP21URI()
        print("")
        
        print("4. Query by Format")
        queryByFormat()
        print("")
        
        print("5. Filter by Network")
        filterByNetwork()
        print("")
        
        print("6. Filter Multi-Destination by Network")
        filterMultiDestinationByNetwork()
        print("")
        
        print("7. Create Unified BIP-21 URI")
        createUnifiedBIP21URI()
        print("")
        
        print("8. Create from PaymentRequest")
        createFromPaymentRequest()
        print("")
        
        print("9. Display Payment Options")
        displayPaymentOptions()
        print("")
    }
}
