//
//  DeleteWalletSettingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct DeleteWalletSettingView: View {
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.walletDataCleanupService) private var cleanupService
    @State private var showingDeletionConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var deletionStrategy: DeletionStrategy?
    /// Which devices keep this deletion local. Nil while checking, and also when
    /// the registries couldn't be read — see `introText`.
    @State private var blockerReport: OtherDeviceReport?
    /// Set when the user takes the informed override. Reset on sheet dismissal so
    /// it can never leak into a subsequent, ordinary deletion.
    @State private var overrideRequested = false
    @State private var isCheckingDevices = true
    @State private var deletionSummary: DeletionSummary?
    
    let onWalletDeleted: (() -> Void)?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                /*
                Image("delete-wallet")
                    .resizable()
                    .aspectRatio(800/500, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                 */
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "action_delete_wallet", defaultValue: "Delete wallet"))
                        .font(.system(.title, design: .serif))
                    
                    Text(introText)
                        .font(.title3)
                        .lineSpacing(6)
                        .foregroundColor(.secondary)
                
                    if let deleteError = deleteError {
                        ErrorBox(errorMessage: deleteError)
                            .padding(.top, 8)
                    }
                    
                    // Balance warning if user has funds
                    if let balance = walletManager.totalBalance, balance.grandTotalSat > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Label {
                                Text(String(localized: "settings_delete_balance_warning", defaultValue: "You still have funds in your wallet. Make sure to transfer them out before deleting, or accept that small amounts below minimum fees may not be recoverable."))
                                    .font(.callout)
                                    .foregroundColor(.primary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.1))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                }
                        }
                        .padding(.top, 8)
                    }
                    
                    // Manual backup reminder
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            Text(String(localized: "settings_delete_backup_reminder", defaultValue: "Have you completed a manual backup? You need both your recovery phrase and wallet state file to fully restore your wallet."))
                                .font(.callout)
                                .foregroundColor(.primary)
                        } icon: {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.Arke.gold2)
                                .frame(width: 20, height: 20)
                        }
                        
                        #if os(iOS)
                        NavigationLink {
                            ManualBackupView_iOS()
                                .navigationTitle(L10n.settingsManualBackup)
                                .navigationBarTitleDisplayMode(.large)
                        } label: {
                            Text(String(localized: "button_manual_backup", defaultValue: "Back up Wallet"))
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.Arke.gold2)
                        .padding(.leading, 30)
                        #endif
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.Arke.gold.opacity(0.1))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.Arke.gold.opacity(0.3), lineWidth: 1)
                            }
                    }
                    .padding(.top, 8)
                    
                    // Show deletion progress
                    if let progress = cleanupService.deletionProgress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: progress.progressPercentage)
                                .progressViewStyle(.linear)
                        }
                        .padding(.top, 8)
                    }
                                        
                    // Show device status
                    if isCheckingDevices {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "status_checking_devices", defaultValue: "Checking for other devices..."))
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    } else if deletionStrategy != nil {
                        // Single delete button
                        Button {
                            showingDeletionConfirmation = true
                        } label: {
                            HStack {
                                Text(L10n.buttonDeleteWallet)
                                    .font(.system(size: 19, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(.vertical, 4)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .tint(Color.Arke.red)
                        .disabled(isDeleting)
                        .padding(.top, 15)

                        // The way out of a blocked full wipe. Deliberately plain
                        // and secondary: the blocking evidence is usually right,
                        // and this path destroys the account's seed. But without
                        // it the wallet cannot be removed from the account at
                        // all — a mirror entry for a device that is genuinely
                        // gone blocks forever, with no staleness cutoff that
                        // could safely age it out (2026-09-23).
                        if showsOverrideOption {
                            Button {
                                overrideRequested = true
                                showingDeletionConfirmation = true
                            } label: {
                                Text(String(localized: "button_delete_from_account_anyway",
                                            defaultValue: "Delete from the account anyway…"))
                                    .font(.callout)
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.Arke.red)
                            .disabled(isDeleting)
                            .padding(.top, 10)
                        }
                    }
                }
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .task {
            await checkDevices()
        }
        .sheet(isPresented: $showingDeletionConfirmation, onDismiss: { overrideRequested = false }) {
            if let strategy = deletionStrategy {
                DeletePermanentlyConfirmationView(
                    deletionStrategy: strategy,
                    onConfirm: {
                        // Shared data (CloudKit, iCloud backup, seed) goes only
                        // when this is the last device — or when the user has
                        // explicitly overridden that verdict
                        await deleteWallet(
                            includeCloudData: WalletDataCleanupService.includesCloudData(
                                strategy: strategy,
                                overrideConfirmed: overrideRequested
                            )
                        )
                    },
                    onBack: {
                        showingDeletionConfirmation = false
                    },
                    isOverride: overrideRequested,
                    blockers: blockerReport?.others ?? []
                )
            }
        }
    }

    /// Whether to offer the informed override — see
    /// `WalletDataCleanupService.shouldOfferOverride(strategy:report:)` for why
    /// a healthy, named blocker does not qualify.
    private var showsOverrideOption: Bool {
        guard let deletionStrategy else { return false }

        return WalletDataCleanupService.shouldOfferOverride(
            strategy: deletionStrategy,
            report: blockerReport
        )
    }
    
    /// Strategy-specific intro; neutral while the device check is still running.
    ///
    /// The `.localOnly` copy names the devices that keep the wallet, because the
    /// unqualified claim ("your other devices keep access") was unfalsifiable
    /// from inside the app: it reads the fast KVS mirror while Linked Devices
    /// reads the CloudKit registry, and on 2026-09-23 they disagreed with no way
    /// for the user to tell which was right.
    private var introText: String {
        switch deletionStrategy {
        case .localOnly:
            guard let report = blockerReport else {
                // Registries unreadable — the strategy is conservative by
                // design, and the copy must not invent devices to justify it
                return String(localized: "settings_delete_warning_check_failed", defaultValue: "This will permanently delete your wallet from this device. Your other devices couldn't be checked, so the wallet stays on the account.")
            }

            let names = report.others.compactMap(\.deviceName)
            if !names.isEmpty {
                return String(format: String(localized: "settings_delete_warning_local_only_named %@", defaultValue: "This will permanently delete your wallet from this device. Still registered elsewhere: %@."),
                              names.formatted(.list(type: .and)))
            }

            // Blockers exist but nothing can name them: mirror entries whose
            // registry rows haven't arrived, or never will
            return String(localized: "settings_delete_warning_local_only_unnamed", defaultValue: "This will permanently delete your wallet from this device. Another device on this iCloud account is still registered to the wallet, though its details haven't reached this device yet.")
        case .promptForCloudData:
            return String(localized: "settings_delete_warning_icloud", defaultValue: "This will permanently delete your wallet from this device and iCloud. All linked devices will lose access.")
        case nil:
            return String(localized: "settings_delete_warning_device", defaultValue: "This will permanently delete your wallet from this device.")
        }
    }

    private func checkDevices() async {
        isCheckingDevices = true
        deleteError = nil

        // Strategy and evidence together: the copy above names the blockers
        let assessment = await cleanupService.assessDeletion()

        await MainActor.run {
            deletionStrategy = assessment.strategy
            blockerReport = assessment.report
            isCheckingDevices = false
        }
    }
    
    private func deleteWallet(includeCloudData: Bool) async {
        isDeleting = true
        deleteError = nil
        deletionSummary = nil
        
        do {
            // Delete all wallet data using the cleanup service
            let summary = try await cleanupService.deleteWalletData(includeCloudData: includeCloudData)
            
            // Delete from WalletManager (this clears local wallet state from bark)
            _ = try await walletManager.deleteWallet()
            
            // Store summary
            deletionSummary = summary
            
            #if DEBUG
            print("✅ [DeleteWalletSettingView] Deletion complete: \(summary.summaryDescription)")
            #endif
            
            // Call the completion handler to navigate back to onboarding
            await MainActor.run {
                onWalletDeleted?()
                // Dismiss the confirmation sheet so onboarding flow is visible
                showingDeletionConfirmation = false
            }
        } catch {
            await MainActor.run {
                deleteError = error.localizedDescription
                isDeleting = false
            }
        }
    }
}
