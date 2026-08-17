import SwiftUI
import ArkeUI

struct BackupStatusSectionView_iOS: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var backupInfo: BackupInfo?
    @State private var isBackingUp = false
    @State private var lastBackupResult: BackupResult?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(String(localized: "backup_description", defaultValue: "The backup file includes all transactions from your payments balance."))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if let info = backupInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "backup_last_synced", defaultValue: "Last synced"))
                                .font(.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(info.formattedDate)
                                .font(.body)
                        }
                        
                        HStack {
                            Text(String(localized: "backup_size", defaultValue: "Size"))
                                .font(.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(info.formattedSize)
                                .font(.body)
                        }
                    }
                    .font(.subheadline)
                } else {
                    Text(String(localized: "backup_no_backup_available", defaultValue: "No backup available"))
                        .foregroundColor(.secondary)
                        .font(.body)
                }

                if let result = lastBackupResult {
                    HStack {
                        Image(systemName: result == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(result == .failed ? .red : .green)
                        Text(result == .success ? String(localized: "backup_successful", defaultValue: "Backup successful") : result == .alreadyUpToDate ? String(localized: "backup_already_up_to_date", defaultValue: "Backup already up-to-date") : String(localized: "backup_failed", defaultValue: "Backup failed"))
                            .foregroundColor(result == .failed ? .red : .green)
                    }
                    .font(.body)
                }

                VStack(spacing: 20) {
                    Button(action: {
                        exportBackupFile()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(L10n.buttonDownload)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .disabled(backupInfo == nil)
                    
                    Button(action: {
                        Task {
                            await performManualBackup()
                        }
                    }) {
                        HStack {
                            if isBackingUp {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise.icloud")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            Text(isBackingUp ? String(localized: "backup_syncing", defaultValue: "Syncing..") : String(localized: "backup_sync_now", defaultValue: "Sync Now"))
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .disabled(isBackingUp)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(String(localized: "backup_title", defaultValue: "Backup file"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadBackupInfo()
        }
    }
    
    private func loadBackupInfo() async {
        guard let barkWallet = walletManager.wallet as? BarkWalletFFI else { return }
        backupInfo = await barkWallet.getBackupInfo()
    }
    
    private func performManualBackup() async {
        guard let barkWallet = walletManager.wallet as? BarkWalletFFI else { return }
        
        isBackingUp = true
        lastBackupResult = nil
        
        let success = await barkWallet.backupWallet()
        
        lastBackupResult = success
        isBackingUp = false
        
        // Refresh backup info after backup
        await loadBackupInfo()
        
        // Clear the success/failure message after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            lastBackupResult = nil
        }
    }
    
    private func exportBackupFile() {
        guard let barkWallet = walletManager.wallet as? BarkWalletFFI else { return }
        
        if let url = barkWallet.getShareableBackupFileURL() {
            ShareHelper.share(items: [url])
        }
    }
}
