//
//  L10n.swift
//  Arké
//
//  Single definition point for localized strings used at 3+ call sites
//  (decision D2 in Shared/Docs/Localization/Default_Value_Migration_Plan.md).
//  Keeping one defaultValue per key prevents copy drift between call sites
//  and extraction conflicts in Localizable.xcstrings.
//
//  Generated from Scripts/audit_output/keys.json during the migration;
//  keep alphabetical. Computed properties (not stored) so lookups respect
//  the current locale.
//

import Foundation

enum L10n {
    static var accessibilityContinueToWallet: String {
        String(localized: "accessibility_continue_to_wallet", defaultValue: "Continue to wallet")
    }
    static var accessibilityPaymentQr: String {
        String(localized: "accessibility_payment_qr", defaultValue: "Payment QR code")
    }
    static var accessibilityWalletReady: String {
        String(localized: "accessibility_wallet_ready", defaultValue: "Your wallet is ready")
    }
    static var accessibilityWalletReadyHint: String {
        String(localized: "accessibility_wallet_ready_hint", defaultValue: "Opens your new wallet")
    }
    static var actionClearContact: String {
        String(localized: "action_clear_contact", defaultValue: "Clear contact")
    }
    static var actionEditAddress: String {
        String(localized: "action_edit_address", defaultValue: "Edit address")
    }
    static var actionRemove: String {
        String(localized: "action_remove", defaultValue: "Remove")
    }
    static var actionSendAddress: String {
        String(localized: "action_send_address", defaultValue: "Send to this address")
    }
    static var activityFeesPaid: String {
        String(localized: "activity_fees_paid", defaultValue: "Fees paid")
    }
    static var activityFeeSummary: String {
        String(localized: "activity_fee_summary", defaultValue: "Fee Summary")
    }
    static var activityFromAddress: String {
        String(localized: "activity_from_address", defaultValue: "From Address")
    }
    static var activityNetworkFee: String {
        String(localized: "activity_network_fee", defaultValue: "Network Fee")
    }
    static var activityToAddress: String {
        String(localized: "activity_to_address", defaultValue: "To Address")
    }
    static var activityTransactionId: String {
        String(localized: "activity_transaction_id", defaultValue: "Transaction ID")
    }
    static var activityUnconfirmed: String {
        String(localized: "activity_unconfirmed", defaultValue: "Unconfirmed")
    }
    static var appName: String {
        String(localized: "app_name", defaultValue: "Arké")
    }
    static var balanceRefreshNow: String {
        String(localized: "balance_refresh_now", defaultValue: "Refresh now")
    }
    static var balanceVtxoRefreshNote: String {
        String(localized: "balance_vtxo_refresh_note", defaultValue: "Note: This VTXO may no longer exist. Make sure to manually refresh the VTXO list on the left.")
    }
    static var buttonBack: String {
        String(localized: "button_back", defaultValue: "Back")
    }
    static var buttonCancel: String {
        String(localized: "button_cancel", defaultValue: "Cancel")
    }
    static var buttonClose: String {
        String(localized: "button_close", defaultValue: "Close")
    }
    static var buttonDelete: String {
        String(localized: "button_delete", defaultValue: "Delete")
    }
    static var buttonDeleteContact: String {
        String(localized: "button_delete_contact", defaultValue: "Delete Contact")
    }
    static var buttonDeleteWallet: String {
        String(localized: "button_delete_wallet", defaultValue: "Delete Wallet")
    }
    static var buttonDismiss: String {
        String(localized: "button_dismiss", defaultValue: "Dismiss")
    }
    static var buttonDone: String {
        String(localized: "button_done", defaultValue: "Done")
    }
    static var buttonDownload: String {
        String(localized: "button_download", defaultValue: "Download")
    }
    static var buttonEdit: String {
        String(localized: "button_edit", defaultValue: "Edit")
    }
    static var buttonImportWallet: String {
        String(localized: "button_import_wallet", defaultValue: "Import Wallet")
    }
    static var buttonOk: String {
        String(localized: "button_ok", defaultValue: "OK")
    }
    static var buttonRetry: String {
        String(localized: "button_retry", defaultValue: "Retry")
    }
    static var buttonSave: String {
        String(localized: "button_save", defaultValue: "Save")
    }
    static var buttonSend: String {
        String(localized: "button_send", defaultValue: "Send")
    }
    static var buttonShare: String {
        String(localized: "button_share", defaultValue: "Share")
    }
    static var buttonStart: String {
        String(localized: "button_start", defaultValue: "Start")
    }
    static var buttonTryAgain: String {
        String(localized: "button_try_again", defaultValue: "Try Again")
    }
    static var buttonUnlink: String {
        String(localized: "button_unlink", defaultValue: "Unlink")
    }
    static var contactsTitle: String {
        String(localized: "contacts_title", defaultValue: "Contacts")
    }
    static var dataProcessing: String {
        String(localized: "data_processing", defaultValue: "Processing")
    }
    static var dataTechnicalDetails: String {
        String(localized: "data_technical_details", defaultValue: "Details")
    }
    static var dataUnknown: String {
        String(localized: "data_unknown", defaultValue: "Unknown")
    }
    static var dataXrayTitle: String {
        String(localized: "data_xray_title", defaultValue: "X-Ray")
    }
    static var errorFilePicker: String {
        String(localized: "error_file_picker", defaultValue: "Failed to select file: %@")
    }
    static var errorTitle: String {
        String(localized: "error_title", defaultValue: "Error")
    }
    static var feeFree: String {
        String(localized: "fee_free", defaultValue: "Free")
    }
    static var feeNetworkWithCount: String {
        String(localized: "fee_network_with_count", defaultValue: "%1$@ network (%2$lld)")
    }
    static var feeTransactions: String {
        String(localized: "fee_transactions", defaultValue: "Transactions")
    }
    static var labelAddress: String {
        String(localized: "label_address", defaultValue: "Address")
    }
    static var labelAmount: String {
        String(localized: "label_amount", defaultValue: "Amount")
    }
    static var labelChange: String {
        String(localized: "label_change", defaultValue: "Change")
    }
    static var labelDetails: String {
        String(localized: "label_details", defaultValue: "Details")
    }
    static var labelFee: String {
        String(localized: "label_fee", defaultValue: "Fee")
    }
    static var labelNoFee: String {
        String(localized: "label_no_fee", defaultValue: "No fee")
    }
    static var labelUsagePattern: String {
        String(localized: "label_usage_pattern", defaultValue: "Usage pattern")
    }
    static var networkArk: String {
        String(localized: "network_ark", defaultValue: "Ark")
    }
    static var networkBitcoin: String {
        String(localized: "network_bitcoin", defaultValue: "Bitcoin")
    }
    static var networkLightning: String {
        String(localized: "network_lightning", defaultValue: "Lightning")
    }
    static var onboardingCreatingWallet: String {
        String(localized: "onboarding_creating_wallet", defaultValue: "Creating wallet")
    }
    static var placeholderAddNote: String {
        String(localized: "placeholder_add_note", defaultValue: "Add a note...")
    }
    static var placeholderEnterAmount: String {
        String(localized: "placeholder_enter_amount", defaultValue: "Enter amount")
    }
    static var placeholderSearchContacts: String {
        String(localized: "placeholder_search_contacts", defaultValue: "Search contacts")
    }
    static var progressLoadingAddress: String {
        String(localized: "progress_loading_address", defaultValue: "Loading address...")
    }
    static var receiveAddressHistory: String {
        String(localized: "receive_address_history", defaultValue: "Address History")
    }
    static var receiveScanToPayTitle: String {
        String(localized: "receive_scan_to_pay_title", defaultValue: "Scan to Pay")
    }
    static var sectionDeviceRole: String {
        String(localized: "section_device_role", defaultValue: "Device Role")
    }
    static var settingsAddressPatterns: String {
        String(localized: "settings_address_patterns", defaultValue: "Address Patterns")
    }
    static var settingsBitcoinFormat: String {
        String(localized: "settings_bitcoin_format", defaultValue: "Bitcoin Amount Format")
    }
    static var settingsDangerZone: String {
        String(localized: "settings_danger_zone", defaultValue: "Danger Zone")
    }
    static var settingsFeeSchedule: String {
        String(localized: "settings_fee_schedule", defaultValue: "Fee Schedule")
    }
    static var settingsLinkedDevices: String {
        String(localized: "settings_linked_devices", defaultValue: "Devices")
    }
    static var settingsManualBackup: String {
        String(localized: "settings_manual_backup", defaultValue: "Manual Backup")
    }
    static var settingsTheme: String {
        String(localized: "settings_theme", defaultValue: "Theme")
    }
    static var settingsThisDeviceParentheses: String {
        String(localized: "settings_this_device_parentheses", defaultValue: "(This Device)")
    }
    static var settingsTitle: String {
        String(localized: "settings_title", defaultValue: "Settings")
    }
    static var statusConfirmed: String {
        String(localized: "status_confirmed", defaultValue: "Confirmed")
    }
    static var statusCopiedExclaim: String {
        String(localized: "status_copied_exclaim", defaultValue: "Copied!")
    }
    static var statusFullWallet: String {
        String(localized: "status_full_wallet", defaultValue: "Primary")
    }
    static var statusMetadataOnly: String {
        String(localized: "status_metadata_only", defaultValue: "Secondary")
    }
    static var statusPaymentReceived: String {
        String(localized: "status_payment_received", defaultValue: "Payment received")
    }
    static var statusPending: String {
        String(localized: "status_pending", defaultValue: "Pending")
    }
    static var statusValid: String {
        String(localized: "status_valid", defaultValue: "Valid")
    }
    static var symbolBullet: String {
        String(localized: "symbol_bullet", defaultValue: "•")
    }
    static var symbolEllipsis: String {
        String(localized: "symbol_ellipsis", defaultValue: "…")
    }
    static var symbolEmDash: String {
        String(localized: "symbol_em_dash", defaultValue: "—")
    }
    static var tagsTitle: String {
        String(localized: "tags_title", defaultValue: "Tags")
    }
    static var transactionCancelled: String {
        String(localized: "transaction_cancelled", defaultValue: "Cancelled")
    }
    static var transactionDetailFromPayments: String {
        String(localized: "transaction_detail_from_payments", defaultValue: "From payments.")
    }
    static var transactionDetailFromSavings: String {
        String(localized: "transaction_detail_from_savings", defaultValue: "From savings.")
    }
    static var transactionDetailPaymentsToSavings: String {
        String(localized: "transaction_detail_payments_to_savings", defaultValue: "From payments to savings.")
    }
    static var transactionDetailSavingsToPayments: String {
        String(localized: "transaction_detail_savings_to_payments", defaultValue: "From savings to payments.")
    }
    static var transactionFailedMove: String {
        String(localized: "transaction_failed_move", defaultValue: "Failed move")
    }
    static var transactionFailedReceive: String {
        String(localized: "transaction_failed_receive", defaultValue: "Failed receive")
    }
    static var transactionFailedSend: String {
        String(localized: "transaction_failed_send", defaultValue: "Failed send")
    }
    static var transactionMoved: String {
        String(localized: "transaction_moved", defaultValue: "Moved")
    }
    static var transactionMoving: String {
        String(localized: "transaction_moving", defaultValue: "Moving")
    }
    static var transactionPending: String {
        String(localized: "transaction_pending", defaultValue: "Pending...")
    }
    static var transactionReceived: String {
        String(localized: "transaction_received", defaultValue: "Received")
    }
    static var transactionReceiving: String {
        String(localized: "transaction_receiving", defaultValue: "Receiving")
    }
    static var transactionSending: String {
        String(localized: "transaction_sending", defaultValue: "Sending")
    }
    static var transactionSent: String {
        String(localized: "transaction_sent", defaultValue: "Sent")
    }
}
