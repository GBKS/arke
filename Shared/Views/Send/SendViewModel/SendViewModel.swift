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
import SwiftData
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
    let modelContext: ModelContext
    
    /// Cached Lightning fee estimate in satoshis
    var cachedLightningFee: Int?
    /// Amount used for the cached Lightning fee (to invalidate cache when amount changes)
    var cachedLightningFeeAmount: Int?
    /// A Lightning fee request is open; the row says "estimating" instead of a dash
    var isEstimatingLightningFee: Bool = false
    /// Generation of the newest Lightning fee request; an older reply is
    /// dropped and the flag clears only with the newest request
    var lightningFeeRequestGeneration: Int = 0
    
    /// Cached Ark fee estimate in satoshis
    var cachedArkFee: Int?
    /// Amount used for the cached Ark fee (to invalidate cache when amount changes)
    var cachedArkFeeAmount: Int?

    /// bark's fee for paying a bitcoin address from the Payments balance
    /// (`Features/Send_Onchain_From_Payments.md` §2.2), with the address
    /// and amount it was priced for; a quote for other inputs does not count
    var cachedOffboardFee: Int?
    var cachedOffboardFeeAmount: Int?
    var cachedOffboardFeeAddress: String?
    /// An offboard fee request is open; the row says "estimating"
    var isEstimatingOffboardFee: Bool = false
    /// Generation of the newest offboard fee request; older replies are dropped
    var offboardFeeRequestGeneration: Int = 0
    
    /// Exact onchain fees per tier for one address, amount and rate set,
    /// from the shadow BDK wallet. A quote for any other inputs does not
    /// count (see `OnchainFeeQuote.matches`), so nothing invalidates it by
    /// hand; it is replaced or cleared.
    var onchainFeeQuote: OnchainFeeQuote?
    /// Generation of the newest onchain quote request. A reply from an older
    /// request is dropped, and the row shows "estimating" only while the
    /// newest one is open.
    var onchainFeeRequestGeneration: Int = 0
    var isEstimatingOnchainFee: Bool = false
    
    // MARK: - State
    var manualInput: String = ""
    /// The amount to send, in whole sats, as a string — the single source of
    /// truth for fees, validation and execution. In fiat entry mode this is
    /// written once per fiat keystroke (see SendViewModel+FiatEntry).
    var amount: String = ""

    // MARK: - Fiat Entry (Fiat_Rates.md §7, Phase 4)
    /// Entry mode and the sats captured at the last fiat keystroke
    var amountEntry = AmountEntryState()
    /// The fiat field's text as typed on the decimal pad (locale separator)
    var fiatAmountText: String = ""
    /// The bitcoin field's text as typed, in the user's unit format ("0.5"
    /// under a decimal format, "50000" under sats) — parsed into `amount`
    var bitcoinAmountText: String = ""
    /// The destination being paid. Views may set it directly from a parsed
    /// address; a new destination resets the source to its default so a
    /// Payments choice made for one address never carries to another.
    var selectedDestination: PaymentDestination? {
        didSet {
            if oldValue?.id != selectedDestination?.id {
                selectedBalanceSource = nil
            }
        }
    }
    /// The balance the selected destination is paid from; nil means the
    /// destination's default (`PaymentDestinationSelector.balanceSource(for:)`).
    /// Set through `select(_:)` / `selectedChoice`, never auto-switched while
    /// the amount is typed (DECIDED rule 3, 2026-10-10).
    var selectedBalanceSource: PaymentDestinationSelector.BalanceSource?
    var rankedDestinations: [PaymentDestinationSelector.RankedDestination] = []
    var currentPaymentRequest: PaymentRequest?
    var error: String?
    var recipientState: RecipientState = .idle
    var sendMode: SendMode = .manual
    var showAddressFormatsPopover = false
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
    
    // MARK: - Pending Metadata (Phase 1)
    /// Pending metadata for the current send operation
    /// Created when payment starts, matched to transaction when movement arrives
    var pendingMetadata: PendingPaymentMetadata?
    
    init(walletManager: WalletManager, clipboardService: ClipboardServiceProtocol, modelContext: ModelContext) {
        self.walletManager = walletManager
        self.clipboardService = clipboardService
        self.modelContext = modelContext
    }
}
