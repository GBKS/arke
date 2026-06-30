//
//  ContactDetailViewModel.swift
//  Arké
//
//  Created by Assistant on 12/8/25.
//

import SwiftUI
import ArkeUI
import UserNotifications

/// Shared view model for contact detail management across macOS and iOS
@Observable
@MainActor
final class ContactDetailViewModel {
    
    // MARK: - Dependencies
    
    let contact: ContactModel
    private let serviceContainer: ServiceContainer
    private let walletManager: WalletManager?
    
    // MARK: - State
    
    var showingContactImport = false
    var alertMessage: String?
    var showingAlert = false
    
    // Faucet state
    var isRequestingFaucet = false
    var faucetAlertMessage: String?
    var faucetAlertType: FaucetAlertType?
    var faucetTransactionId: String? // Store txid for "View Transaction" button
    var showingFaucetAlert = false
    
    // MARK: - Initialization
    
    init(contact: ContactModel, serviceContainer: ServiceContainer, walletManager: WalletManager? = nil) {
        self.contact = contact
        self.serviceContainer = serviceContainer
        self.walletManager = walletManager
    }
    
    // MARK: - Computed Properties
    
    var hasTransactionData: Bool {
        contact.transactionCount != nil || contact.sentAmount != nil || contact.receivedAmount != nil
    }
    
    // MARK: - Native Contact Actions
    
    func handleRefreshFromNativeContact() async {
        do {
            _ = try await serviceContainer.contactService.refreshFromNativeContact(contactID: contact.id)
            print("✅ Successfully refreshed contact from native Contacts")
            alertMessage = "Successfully refreshed contact from native Contacts"
            showingAlert = true
        } catch {
            print("❌ Failed to refresh from native contact: \(error)")
            alertMessage = "Failed to refresh from native contact: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    func handleUnlinkFromNativeContact() async {
        do {
            try await serviceContainer.contactService.unlinkFromNativeContact(contactID: contact.id)
            print("✅ Successfully unlinked contact from native Contacts")
            alertMessage = "Successfully unlinked contact from native Contacts"
            showingAlert = true
        } catch {
            print("❌ Failed to unlink from native contact: \(error)")
            alertMessage = "Failed to unlink from native contact: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    func handleLinkToNativeContact() {
        showingContactImport = true
    }
    
    func handleContactImportSelection(_ importedData: ImportedContactData) async {
        do {
            // Check if this native contact is already imported
            let isAlreadyImported = await serviceContainer.contactService.isNativeContactImported(importedData.identifier)
            
            if isAlreadyImported {
                alertMessage = "This native contact is already linked to another contact in your wallet."
                showingAlert = true
                return
            }
            
            // Link the contact
            _ = try await serviceContainer.contactService.linkToNativeContact(
                contactID: contact.id,
                nativeContactData: importedData
            )
            
            print("✅ Successfully linked contact to native Contacts")
            alertMessage = "Successfully linked contact to \(importedData.fullName)"
            showingAlert = true
            
        } catch {
            print("❌ Failed to link to native contact: \(error)")
            alertMessage = "Failed to link to native contact: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}
// MARK: - Faucet Alert Type

enum FaucetAlertType {
    case success
    case error
    case rateLimited
    case insufficientFunds
}

// MARK: - Notification Prompt Action

enum NotificationPromptAction {
    case promptForPermission  // Show in-app prompt to request permission
    case openSettings         // User previously denied, need to open Settings
    case alreadyAuthorized    // No action needed
}

// MARK: - Notification Permission

extension ContactDetailViewModel {
    
    /// Check notification authorization status
    func checkNotificationStatus() async -> NotificationPromptAction {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .notDetermined:
            // Never asked before - we can prompt
            return .promptForPermission
        case .denied:
            // User previously denied - need to go to Settings
            return .openSettings
        case .authorized, .provisional, .ephemeral:
            // Already authorized - no prompt needed
            return .alreadyAuthorized
        @unknown default:
            return .alreadyAuthorized
        }
    }
    
    /// Register for notifications (called when user accepts prompt)
    func registerForNotifications() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            if granted {
                print("✅ User granted notification permission")
                
                #if os(iOS)
                // IMPORTANT: Update UserDefaults BEFORE registering with relay
                // The relay registration checks this flag
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "notifications_enabled")
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Wait for token
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                // Register with relay (will now succeed because flag is set)
                await walletManager?.registerForPushNotifications()
                #endif
                
                print("✅ Successfully registered for notifications")
                return true
            } else {
                print("⚠️ User denied notification permission")
                return false
            }
        } catch {
            print("❌ Failed to register for notifications: \(error)")
            return false
        }
    }
}

// MARK: - Faucet Actions

extension ContactDetailViewModel {
    
    /// Request signet bitcoin from faucet (with optional notification prompt)
    func requestSignetFaucet(toAddress address: String, onSuccess: (() -> Void)? = nil) async {
        isRequestingFaucet = true
        defer { isRequestingFaucet = false }
        
        print("🪙 Requesting signet faucet for address: \(address)")
        
        do {
            let response = try await serviceContainer.signetFaucetService.requestFaucet(toAddress: address)
            
            if response.isSuccess {
                faucetAlertMessage = response.message ?? "Successfully requested testnet bitcoin!"
                faucetAlertType = .success
                faucetTransactionId = response.txid // Store the txid
                showingFaucetAlert = true
                
                // Call success callback after a brief delay to allow the UI to show success state
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    onSuccess?()
                }
            } else {
                faucetAlertMessage = response.message ?? "Request completed with unknown status"
                faucetAlertType = .error
                faucetTransactionId = nil
                showingFaucetAlert = true
            }
            
        } catch let error as FaucetError {
            faucetTransactionId = nil
            handleFaucetError(error)
        } catch {
            faucetTransactionId = nil
            faucetAlertMessage = "Unexpected error: \(error.localizedDescription)"
            faucetAlertType = .error
            showingFaucetAlert = true
        }
    }
    
    private func handleFaucetError(_ error: FaucetError) {
        switch error {
        case .rateLimited:
            faucetAlertMessage = error.localizedDescription
            faucetAlertType = .rateLimited
        case .insufficientFunds:
            faucetAlertMessage = error.localizedDescription
            faucetAlertType = .insufficientFunds
        default:
            faucetAlertMessage = error.localizedDescription
            faucetAlertType = .error
        }
        showingFaucetAlert = true
    }
}

