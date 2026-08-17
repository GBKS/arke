//
//  L10n.swift
//  ArkéUI
//
//  Package-internal single definition point for localized strings used at
//  3+ call sites (decision D2 in
//  Shared/Docs/Localization/Default_Value_Migration_Plan.md). Mirrors the
//  app-side Shared/Helpers/L10n.swift; both modules keep their own namespace
//  (this one is internal, so it never collides with the app's L10n).
//
//  Grows batch by batch during the defaultValue migration; keep alphabetical.
//  Computed properties (not stored) so lookups respect the current locale.
//

import Foundation

enum L10n {

    static var buttonCancel: String {
        String(localized: "button_cancel", defaultValue: "Cancel", bundle: .module)
    }

    static var buttonClose: String {
        String(localized: "button_close", defaultValue: "Close", bundle: .module)
    }

    static var buttonDone: String {
        String(localized: "button_done", defaultValue: "Done", bundle: .module)
    }

    static var buttonRetry: String {
        String(localized: "button_retry", defaultValue: "Retry", bundle: .module)
    }

    static var buttonStart: String {
        String(localized: "button_start", defaultValue: "Start", bundle: .module)
    }

    static var feeTransactions: String {
        String(localized: "fee_transactions", defaultValue: "Transactions", bundle: .module)
    }

    static var formatZero: String {
        String(localized: "format_zero", defaultValue: "0", bundle: .module)
    }

    static var labelAmount: String {
        String(localized: "label_amount", defaultValue: "Amount", bundle: .module)
    }

    static var labelFee: String {
        String(localized: "label_fee", defaultValue: "Fee", bundle: .module)
    }

    static var labelNextRound: String {
        String(localized: "label_next_round", defaultValue: "Next round", bundle: .module)
    }

    static var labelStatus: String {
        String(localized: "label_status", defaultValue: "Status", bundle: .module)
    }

    static var placeholderAddNote: String {
        String(localized: "placeholder_add_note", defaultValue: "Add a note...", bundle: .module)
    }

    static var placeholderAmountOptional: String {
        String(localized: "placeholder_amount_optional", defaultValue: "Add amount (optional)", bundle: .module)
    }

    static var placeholderEnterAmount: String {
        String(localized: "placeholder_enter_amount", defaultValue: "Enter amount", bundle: .module)
    }

    static var placeholderNoteOptional: String {
        String(localized: "placeholder_note_optional", defaultValue: "Add note (optional)", bundle: .module)
    }

    static var statusConfirmed: String {
        String(localized: "status_confirmed", defaultValue: "Confirmed", bundle: .module)
    }

    static var statusCopiedExclaim: String {
        String(localized: "status_copied_exclaim", defaultValue: "Copied!", bundle: .module)
    }

    static var statusRefreshing: String {
        String(localized: "status_refreshing", defaultValue: "Refreshing...", bundle: .module)
    }

    static var symbolEllipsis: String {
        String(localized: "symbol_ellipsis", defaultValue: "…", bundle: .module)
    }

    static var transactionReceived: String {
        String(localized: "transaction_received", defaultValue: "Received", bundle: .module)
    }

    static var transactionSent: String {
        String(localized: "transaction_sent", defaultValue: "Sent", bundle: .module)
    }
}
