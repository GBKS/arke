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
                    Text("action_delete_wallet")
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
                                Text(String(localized: "settings_delete_balance_warning"))
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
                            Text(String(localized: "settings_delete_backup_reminder"))
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
                                .navigationTitle("settings_manual_backup")
                                .navigationBarTitleDisplayMode(.large)
                        } label: {
                            Text("button_manual_backup")
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
                            Text(String(localized: "status_checking_devices"))
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
                                Text("button_delete_wallet")
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
                    }
                }
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .task {
            await checkDevices()
        }
        .sheet(isPresented: $showingDeletionConfirmation) {
            if let strategy = deletionStrategy {
                DeletePermanentlyConfirmationView(
                    deletionStrategy: strategy,
                    onConfirm: {
                        // Only wipe shared data (CloudKit, iCloud backup, seed) when
                        // this is the last device; with other active devices the
                        // wallet keeps living on them and one can be promoted
                        await deleteWallet(includeCloudData: strategy == .promptForCloudData)
                    },
                    onBack: {
                        showingDeletionConfirmation = false
                    }
                )
            }
        }
    }
    
    /// Strategy-specific intro; neutral while the device check is still running
    private var introText: String {
        switch deletionStrategy {
        case .localOnly:
            return String(localized: "settings_delete_warning_local_only", defaultValue: "This will permanently delete your wallet from this device. Your other devices keep access to the wallet.")
        case .promptForCloudData:
            return String(localized: "settings_delete_warning_icloud")
        case nil:
            return String(localized: "settings_delete_warning_device", defaultValue: "This will permanently delete your wallet from this device.")
        }
    }

    private func checkDevices() async {
        isCheckingDevices = true
        deleteError = nil
        
        // Get deletion strategy based on other devices
        let strategy = await cleanupService.getDeletionStrategy()
        
        await MainActor.run {
            deletionStrategy = strategy
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
