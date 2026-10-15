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
    /// The two-word phrase check, pushed in front of the slider sheet on a
    /// full wipe (DECIDED 2026-10-15). The sheet, the deletion call and the
    /// abort handling stay here; the pushed screen only reports a pass.
    @State private var showingPhraseConfirmation = false
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

                    // Manual export, full-wipe path only, right under the
                    // sentence that asks for it: the wipe empties the iCloud
                    // backup slot and the mirrored history, so the user's own
                    // file is the only way to restore history. A local-only
                    // deletion writes its final state file to the slot itself
                    // and the other devices keep the mirrored rows (Christoph,
                    // 2026-10-15), so there is nothing to ask for.
                    #if os(iOS)
                    if isFullWipePath {
                        NavigationLink {
                            ManualBackupView_iOS()
                                .navigationTitle(L10n.settingsManualBackup)
                                .navigationBarTitleDisplayMode(.large)
                        } label: {
                            HStack(spacing: 4) {
                                Text(String(localized: "button_manual_backup", defaultValue: "Back up Wallet"))
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.Arke.gold2)
                    }
                    #endif

                    if let deleteError = deleteError {
                        ErrorBox(errorMessage: deleteError)
                            .padding(.top, 8)
                    }
                    
                    // Forfeit warning: a Payments balance expiry will sweep once
                    // nothing refreshes it. Onchain coins come back with the
                    // phrase and get no box (DECIDED 2026-10-13).
                    // Row with a filled icon tile (the transaction icon's
                    // tile recipe), no box: the box competed with the intro
                    // and left the glyph looking like a bullet
                    if let warning = forfeitWarning {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                                .frame(width: 44, height: 44)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityHidden(true)

                            Text(forfeitWarningText(warning))
                                .font(.callout)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)
                    }
                    

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
                        // Not the final confirmation (the slider sheet is), so
                        // a regular primary button, not a red one
                        Button {
                            startDeletion(override: false)
                        } label: {
                            Text(String(localized: "button_continue", defaultValue: "Continue"))
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .tint(Color.Arke.gold)
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
                                startDeletion(override: true)
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
        #if os(iOS)
        .navigationDestination(isPresented: $showingPhraseConfirmation) {
            phraseConfirmationScreen
        }
        #else
        .sheet(isPresented: $showingPhraseConfirmation) {
            phraseConfirmationScreen
                .frame(minWidth: 420, minHeight: 420)
        }
        #endif
        .onChange(of: showingPhraseConfirmation) { _, isShowing in
            // Leaving the phrase screen without passing drops the override,
            // so it can never leak into a later, ordinary deletion. A pass
            // that is handing over to the slider sheet (macOS closes the
            // phrase sheet first, see `phraseConfirmationScreen`) keeps it.
            if !isShowing && !showingDeletionConfirmation {
                overrideRequested = false
            }
        }
        .sheet(isPresented: $showingDeletionConfirmation, onDismiss: {
            // The override survives a cancelled sheet only while the phrase
            // screen is still up: the user can slide again from there, and
            // the scope they confirmed on it must be the one that runs
            if !showingPhraseConfirmation {
                overrideRequested = false
            }
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

    private var phraseConfirmationScreen: some View {
        DeletePhraseConfirmationView {
            showingDeletionConfirmation = true
            #if os(macOS)
            // Both are sheets on this view and SwiftUI presents one at a
            // time: close the phrase sheet so the queued slider can appear.
            // The flag order keeps the override (see the onChange above).
            showingPhraseConfirmation = false
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Both delete buttons land here. A full wipe (last device, or the
    /// informed override) goes through the two-word phrase check first;
    /// local-only deletion keeps the seed on the account and opens the
    /// slider sheet directly. The override flag is set explicitly on every
    /// tap so no earlier state can carry over.
    private func startDeletion(override: Bool) {
        overrideRequested = override
        deleteError = nil

        guard let deletionStrategy,
              PhraseConfirmation.isRequired(strategy: deletionStrategy, overrideRequested: override) else {
            showingDeletionConfirmation = true
            return
        }

        showingPhraseConfirmation = true
    }

    /// Whether a full wipe is reachable from this screen: the last-device
    /// strategy, or a `.localOnly` verdict while the override is offered
    /// (same rule as the forfeit warning). Drives the manual-export link.
    private var isFullWipePath: Bool {
        deletionStrategy == .promptForCloudData || showsOverrideOption
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
            // Last device: carries the phrase and backup message too, so the
            // screen has one paragraph instead of an intro plus a reminder box
            return String(localized: "settings_delete_warning_everywhere_intro", defaultValue: "This permanently deletes your wallet from this device and from iCloud, including the recovery phrase.\n\nOnly a copy you wrote down can bring it back, and the next step asks for two of its words. To restore your history as well, back up the wallet state file first.")
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

    /// Re-runs on every return to this screen (sheet dismissal, phrase-screen
    /// pop). It must not clear `deleteError`: the scope-invalidated abort
    /// sets the error and dismisses in the same transaction, and the
    /// re-check would erase it before the user could read it (review
    /// 2026-10-15). The error is cleared when the user starts a new attempt.
    private func checkDevices() async {
        isCheckingDevices = true

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
                showingPhraseConfirmation = false
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
                // Pop the phrase screen too: the error and the new blockers
                // are shown on this screen
                showingPhraseConfirmation = false
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
