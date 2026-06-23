//
//  SendViewModel.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  Architecture:
//  - Three distinct modes: Manual, Contact, and Quick
//  - Single SendState object that all child views can modify
//  - Mode selection happens once on initialization based on context
//  - Quick mode can transition to Manual (confirmed) when user accepts a bare address
//  - All modes can reset back to Manual (entering) via clearAll()
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

/// Shared view model for Send flow across macOS and iOS
@Observable
@MainActor
final class SendViewModel {
    
    // MARK: - Logger
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "SendViewModel")
    
    // MARK: - Send Mode
    enum SendMode {
        case manual           // Manual entry (entering or confirmed)
        case contact(ContactModel)  // Sending to a saved contact
        case quick(PaymentRequest, source: PaymentRequestSource)  // Payment request with source tracking
        
        var description: String {
            switch self {
            case .manual:
                return "manual"
            case .contact(let contact):
                return "contact(\(contact.displayName))"
            case .quick(let request, let source):
                return "quick(\(request.primaryDestination?.shortAddress ?? "unknown"), source: \(source.displayName))"
            }
        }
    }
    
    // MARK: - Dependencies
    // Only use internally by extensions.
    let walletManager: WalletManager
    let clipboardService: ClipboardServiceProtocol
    
    /// Cached Lightning fee estimate in satoshis
    var cachedLightningFee: Int?
    /// Amount used for the cached Lightning fee (to invalidate cache when amount changes)
    var cachedLightningFeeAmount: Int?
    
    /// Cached Ark fee estimate in satoshis
    var cachedArkFee: Int?
    /// Amount used for the cached Ark fee (to invalidate cache when amount changes)
    var cachedArkFeeAmount: Int?
    
    /// Cached onchain fee estimate in satoshis
    var cachedOnchainFee: Int?
    /// Amount used for the cached onchain fee (to invalidate cache when amount changes)
    var cachedOnchainFeeAmount: Int?
    /// Fee priority used for the cached onchain fee (to invalidate cache when priority changes)
    var cachedOnchainFeePriority: FeePriority?
    
    // MARK: - State
    var manualInput: String = ""
    var amount: String = ""
    var selectedDestination: PaymentDestination?
    var rankedDestinations: [PaymentDestinationSelector.RankedDestination] = []
    var currentPaymentRequest: PaymentRequest?
    var error: String?
    var recipientState: RecipientState = .idle
    var sendMode: SendMode = .manual
    var showAddressFormatsPopover = false
    var showDestinationPicker = false
    var sendModalState: SendModalState?
    var showFeeSelectionSheet = false
    var selectedFeePriority: FeePriority = .medium
    var onchainFeeRates: OnchainFeeRates = .default
    
    // MARK: - Clipboard State
    /// Tracks whether clipboard has content available
    var hasClipboardContent: Bool = false
    
    // MARK: - LNURL State
    /// Resolved LNURL-pay data (cached from resolution for payment execution)
    var resolvedLNURL: LNURLResolver.ResolvedLNURL?
    
    // MARK: - Send Max State
    /// Tracks whether the user initiated a "send max" operation
    /// Used to enable retry logic for Lightning payments with dynamic routing fees
    var isSendingMax: Bool = false
    
    /// Callback to dismiss the view after successful payment
    var onDismiss: (() -> Void)?
    
    init(walletManager: WalletManager, clipboardService: ClipboardServiceProtocol) {
        self.walletManager = walletManager
        self.clipboardService = clipboardService
    }
}
