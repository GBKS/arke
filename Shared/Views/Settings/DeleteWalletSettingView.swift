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
    /// Inputs to the forfeit warning, loaded once with the device check. Nil
    /// until loaded, so the box cannot flash the wrong amount.
    @State private var forfeitSummary: DeletionForfeitWarning.Summary?
    @State private var currentBlockHeight: Int?

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
                    
                    // Forfeit warning: a Payments balance expiry will sweep once
                    // nothing refreshes it. Onchain coins come back with the
                    // phrase and get no box (DECIDED 2026-10-13).
                    if let warning = forfeitWarning {
                        VStack(alignment: .leading, spacing: 10) {
                            Label {
                                Text(forfeitWarningText(warning))
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
        .task {
            // Runs alongside the device check so the box is normally ready
            // when the delete button appears
            await loadForfeitInputs()
        }
        .sheet(isPresented: $showingDeletionConfirmation, onDismiss: {
            overrideRequested = false
            // Re-check on every dismissal: the user may have backed out after
            // the evidence changed, and the scope-invalidated abort lands here
            // too — either way the screen should show current blockers.
            Task { await checkDevices() }
        }) {
            if let strategy = deletionStrategy {
                DeletePermanentlyConfirmationView(
                    deletionStrategy: strategy,
                    onConfirm: {
                        // The service derives the scope (shared data goes only
                        // when this is the last device, or on the explicit
                        // override) and re-checks the evidence at the moment
                        // of the wipe
                        await deleteWallet(strategy: strategy, overrideConfirmed: overrideRequested)
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

    /// The funds warning, if any. Needs the strategy (which copy) and the
    /// loaded VTXO summary (whether there is anything to warn about), so it
    /// never appears before the delete button. The override condition picks
    /// the last-device copy, see `DeletionForfeitWarning.resolve`.
    private var forfeitWarning: DeletionForfeitWarning.State? {
        guard let deletionStrategy, let forfeitSummary else { return nil }

        return DeletionForfeitWarning.resolve(
            strategy: deletionStrategy,
            overrideOffered: showsOverrideOption,
            summary: forfeitSummary,
            currentBlockHeight: currentBlockHeight
        )
    }

    /// Four variants: last device vs other devices, with or without a
    /// deadline. "Payments" is the app's name for the Ark balance; the amount
    /// follows the user's unit setting and the time the shared block-time
    /// formatter ("26d 5h").
    private func forfeitWarningText(_ warning: DeletionForfeitWarning.State) -> String {
        let amount = BitcoinFormatter.shared.formatAmount(warning.amountSat)
        let time = warning.blocksUntilExpiry.map { BlockTimeFormatter.duration(forBlocks: $0) }

        switch (warning.scope, time) {
        case (.lastDevice, let time?):
            return String(localized: "settings_delete_forfeit_last_device %@ %@", defaultValue: "Your Payments balance of \(amount) is forfeited in about \(time) unless this wallet is recovered from its recovery phrase and refreshed before then. Send it out first if you can.")
        case (.lastDevice, nil):
            return String(localized: "settings_delete_forfeit_last_device_no_time %@", defaultValue: "Your Payments balance of \(amount) is forfeited at expiry unless this wallet is recovered from its recovery phrase and refreshed before then. Send it out first if you can.")
        case (.otherDevices, let time?):
            return String(localized: "settings_delete_forfeit_other_devices %@ %@", defaultValue: "Your Payments balance of \(amount) needs a refresh within about \(time). After deleting here, open the wallet on another device so it can refresh in time.")
        case (.otherDevices, nil):
            return String(localized: "settings_delete_forfeit_other_devices_no_time %@", defaultValue: "Your Payments balance of \(amount) needs a refresh before it expires. After deleting here, open the wallet on another device so it can refresh in time.")
        }
    }

    /// Per-VTXO expiries need the bark handle. A read-only secondary has none,
    /// so it falls back to the synced balance with no deadline rather than
    /// showing nothing. The box must not wait on the network: the amount is
    /// published as soon as the local VTXO read returns, with the cached
    /// height estimate, and the fresh height only refines the deadline.
    private func loadForfeitInputs() async {
        guard walletManager.isInitialized, !walletManager.isReadOnlyMode else {
            forfeitSummary = syncedForfeitSummary
            return
        }

        do {
            let vtxos = try await walletManager.getVTXOs()
            currentBlockHeight = walletManager.cacheManager.getEstimatedBlockHeight()
            forfeitSummary = DeletionForfeitWarning.summarize(vtxos)
        } catch {
            #if DEBUG
            print("⚠️ [DeleteWalletSettingView] VTXO read failed, warning falls back to the synced balance: \(error.localizedDescription)")
            #endif
            forfeitSummary = syncedForfeitSummary
            return
        }

        if let freshHeight = await walletManager.getEstimatedBlockHeight() {
            currentBlockHeight = freshHeight
        }
    }

    /// The same set the VTXO path counts (bark's Spendable + Locked), read
    /// from the synced balance row: everything in Ark except exits in flight.
    private var syncedForfeitSummary: DeletionForfeitWarning.Summary {
        let ark = walletManager.totalBalance?.arkBalance
        return DeletionForfeitWarning.Summary(
            amountSat: ark.map { $0.totalSat - $0.pendingExitSat } ?? 0,
            earliestExpiryHeight: nil
        )
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
    
    private func deleteWallet(strategy: DeletionStrategy, overrideConfirmed: Bool) async {
        isDeleting = true
        deleteError = nil
        deletionSummary = nil

        // No opportunistic backup may run while the deletion is in flight
        // (contract rule 17); released on every exit of this function
        walletManager.setWalletDeletionInProgress(true)
        defer { walletManager.setWalletDeletionInProgress(false) }

        do {
            // Delete all wallet data using the cleanup service (which
            // re-derives the scope from fresh evidence before the first
            // destructive step)
            let summary = try await cleanupService.deleteWalletData(
                strategy: strategy,
                overrideConfirmed: overrideConfirmed
            )

            // Delete from WalletManager (this clears local wallet state from
            // bark). The scope comes from the deletion that ran, so a full
            // wipe does not re-create the backup the service just removed.
            _ = try await walletManager.deleteWallet(scope: summary.scope)

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
        } catch let WalletCleanupError.fullWipeScopeInvalidated(fresh) {
            // The pre-wipe recheck found a device the screen's assessment
            // didn't know about. Nothing was deleted — surface the updated
            // blockers and drop the override (it was confirmed against
            // evidence that no longer holds).
            #if DEBUG
            print("🛑 [DeleteWalletSettingView] Full wipe aborted: device evidence changed mid-confirmation")
            #endif
            await MainActor.run {
                deletionStrategy = fresh.strategy
                blockerReport = fresh.report
                overrideRequested = false
                showingDeletionConfirmation = false
                deleteError = WalletCleanupError.fullWipeScopeInvalidated(fresh).localizedDescription
                isDeleting = false
            }
        } catch {
            await MainActor.run {
                deleteError = error.localizedDescription
                isDeleting = false
            }
        }
    }
}
