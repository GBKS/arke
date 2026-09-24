//
//  DeletePermanentlyConfirmationView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 1/26/26.
//

import SwiftUI
import ArkeUI

struct DeletePermanentlyConfirmationView: View {
    let deletionStrategy: DeletionStrategy
    let onConfirm: () async -> Void
    let onBack: () -> Void

    /// True when the user is overriding a `.localOnly` verdict to wipe the whole
    /// account anyway. The consequence is the same as any full wipe, but the
    /// premise is not: the registries say other devices still hold this wallet,
    /// and the user is asserting otherwise. So this path names what blocks it and
    /// demands an explicit acknowledgement before the destructive gesture unlocks.
    var isOverride: Bool = false

    /// Devices the registries say still hold the wallet, for the override copy.
    var blockers: [OtherWalletDevice] = []

    @Environment(\.walletDataCleanupService) private var cleanupService
    @State private var isDeleting = false
    @State private var deleteError: String?
    /// Gate on the override path only. The seed is the one thing a wrong full
    /// wipe destroys irrecoverably, so the user confirms they hold it offline.
    @State private var acknowledgedRecoveryPhrase = false

    private var isConfirmEnabled: Bool {
        !isDeleting && (!isOverride || acknowledgedRecoveryPhrase)
    }
    
    var body: some View {
        ZStack {
            // Background image with darker overlay
            Image("wipe-wallet-forever")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .ignoresSafeArea()
            
            VStack {
                // Top bar with back button
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Text(L10n.buttonCancel)
                                .font(.system(size: 17))
                        }
                        .foregroundColor(.white)
                    }
                    .disabled(isDeleting)
                    
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.top, 20)
                
                Spacer()
                
                // Content area
                VStack(spacing: 25) {
                    VStack(spacing: 15) {
                        Text(String(localized: "message_delete_permanently", defaultValue: "Delete Permanently?"))
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text(String(localized: "message_cannot_undo", defaultValue: "This cannot be undone!"))
                            .font(.title2)
                            .foregroundColor(.Arke.red)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text(warningText)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)

                        if isOverride {
                            overrideAcknowledgement
                        }
                        
                        /*
                        // Warning callout for iCloud
                        if case .promptForCloudData = deletionStrategy {
                            VStack(spacing: 12) {
                                Label {
                                    Text("All devices will lose access")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white.opacity(0.95))
                                } icon: {
                                    Image(systemName: "icloud.slash")
                                        .foregroundColor(.Arke.red)
                                }
                                
                                Text("Deleting iCloud data will affect all devices using this wallet. Make sure you have your recovery phrase saved before continuing.")
                                    .font(.callout)
                                    .foregroundColor(.white.opacity(0.85))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 20)
                            }
                            .padding(.vertical, 15)
                            .padding(.horizontal, 20)
                            .background {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.red.opacity(0.25))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15)
                                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                    }
                            }
                            .padding(.top, 10)
                        }
                        
                        // What will be deleted
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What will be deleted:")
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.9))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                DeletionItemRow(icon: "key.fill", text: "Recovery phrase and private keys")
                                DeletionItemRow(icon: "doc.fill", text: "Transaction history")
                                DeletionItemRow(icon: "gearshape.fill", text: "All wallet settings")
                                
                                if case .promptForCloudData = deletionStrategy {
                                    DeletionItemRow(icon: "icloud.fill", text: "iCloud backup data")
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.4))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                }
                        }
                        .padding(.horizontal, 25)
                         */
                    }
                    
                    // Error display
                    if let deleteError = deleteError {
                        ErrorBox(errorMessage: deleteError)
                            .padding(.horizontal, 25)
                    }
                    
                    // Show deletion progress
                    if let progress = cleanupService.deletionProgress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.message)
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.85))
                            
                            ProgressView(value: progress.progressPercentage)
                                .progressViewStyle(.linear)
                                .tint(.Arke.red)
                        }
                        .padding(.horizontal, 25)
                        .padding(.vertical, 15)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.3))
                        }
                        .padding(.horizontal, 25)
                    }
                }
                .padding(.horizontal, 25)
                
                // Confirm button at bottom
                VStack(spacing: 15) {
                    #if os(iOS)
                    SlideToActionButton_iOS(
                        text: String(localized: "button_slide_to_delete", defaultValue: "Slide to Delete"),
                        icon: "trash.fill",
                        tintColor: Color.Arke.red,
                        isEnabled: isConfirmEnabled
                    ) {
                        Task {
                            await performDeletion()
                        }
                    }
                    #else
                    Button {
                        Task {
                            await performDeletion()
                        }
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(isDeleting ? String(localized: "status_deleting_everything", defaultValue: "Deleting Everything...") : confirmButtonTitle)
                                .font(.system(size: 19, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.red)
                    .disabled(!isConfirmEnabled)
                    #endif
                    
                    /*
                    Text("Make sure you have your recovery phrase saved")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    */
                }
                .padding(.horizontal, 25)
                .padding(.top, 25)
                .padding(.bottom, 30)
            }
        }
    }
    
    /// The override's consequence, named devices and all, plus the one
    /// acknowledgement that stands between the user and an unrecoverable wipe.
    private var overrideAcknowledgement: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(blockerSummary)
                .font(.callout)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $acknowledgedRecoveryPhrase) {
                Text(String(localized: "settings_delete_override_acknowledge",
                            defaultValue: "I have my recovery phrase written down. I understand every device on this iCloud account loses this wallet."))
                    .font(.callout)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color.Arke.red)
            .disabled(isDeleting)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.Arke.red.opacity(0.5), lineWidth: 1)
                }
        }
        .padding(.top, 10)
    }

    /// Names what the registries think is still out there. A mirror-only entry
    /// has no name, and saying so is the point — an unnameable blocker is exactly
    /// the situation the override exists for.
    private var blockerSummary: String {
        let names = blockers.compactMap(\.deviceName)

        if !names.isEmpty {
            return String(format: String(localized: "settings_delete_override_blockers %@",
                                         defaultValue: "Still registered to this wallet: %@. If you no longer have them, continuing removes the wallet from the account anyway."),
                          names.formatted(.list(type: .and)))
        }

        return String(localized: "settings_delete_override_blockers_unnamed",
                      defaultValue: "Another device on this iCloud account is still registered to this wallet, but its details never reached this device. If that device is gone, continuing removes the wallet from the account anyway.")
    }

    private var confirmButtonTitle: String {
        if isOverride {
            return String(localized: "button_delete_everywhere_anyway", defaultValue: "Delete Everywhere Anyway")
        }

        switch deletionStrategy {
        case .localOnly:
            return String(localized: "button_delete_from_device", defaultValue: "Delete from This Device")
        case .promptForCloudData:
            return String(localized: "button_delete_everything", defaultValue: "Delete Everything")
        }
    }

    private var warningText: String {
        if isOverride {
            return String(localized: "settings_delete_permanent_warning_override", defaultValue: "This removes the wallet from this device, from iCloud, and from every other device on this iCloud account — including the recovery phrase in iCloud Keychain. Only a phrase you wrote down can restore it.")
        }

        switch deletionStrategy {
        case .localOnly:
            return String(localized: "settings_delete_permanent_warning_local_only", defaultValue: "All wallet data will be permanently deleted from this device. Your other devices keep this wallet — open one of them to make it the active device.")
        case .promptForCloudData:
            return String(localized: "settings_delete_permanent_warning_everywhere", defaultValue: "All wallet data will be permanently deleted from this device and iCloud. No turning back.")
        }
    }

    private func performDeletion() async {
        isDeleting = true
        deleteError = nil

        await onConfirm()
    }
}

// Helper view for deletion items list
struct DeletionItemRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.Arke.red.opacity(0.8))
                .frame(width: 20)
            
            Text(text)
                .font(.callout)
                .foregroundColor(.white.opacity(0.85))
        }
    }
}
