//
//  ImportWalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI
import ArkeUI
import Combine
import Foundation
import UniformTypeIdentifiers
import OSLog

struct ImportWalletView_iOS: View {
    // MARK: - Logging
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ImportWalletView")
    
    // MARK: - Properties
    
    let isMainnet: Bool
    let onBack: () -> Void
    let onWalletImported: () -> Void
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mnemonicPhrase: String = ""
    @State private var backupFileURL: URL?
    @State private var backupFileName: String?
    @State private var showingFilePicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isImporting = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                    HStack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(Color.Arke.gold)
                        .accessibilityLabel(L10n.buttonBack)
                        
                        Spacer()
                    }
                    .padding(.top, 10)
                    
                    VStack(spacing: 8) {
                        Text(String(localized: "onboarding_import_title", defaultValue: "Import Wallet"))
                            .font(.system(.largeTitle, design: .serif))
                            .foregroundStyle(Color.Arke.gold)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text(String(localized: "onboarding_restore_wallet", defaultValue: "Restore your existing wallet with your 12-word recovery phrase."))
                            .font(.system(.title2))
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    TextField(String(localized: "placeholder_enter_recovery_phrase", defaultValue: "Enter your 12-words here..."), text: $mnemonicPhrase, axis: .vertical)
                        .padding(15)
                        .background(Color.primary.opacity(0.05))
                        .foregroundStyle(.white)
                        .font(.system(.title3))
                        .lineSpacing(4)
                        .lineLimit(3...5)
                        .cornerRadius(8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .accessibilityLabel(String(localized: "accessibility_recovery_phrase_field", defaultValue: "Recovery phrase"))
                        .accessibilityHint(String(localized: "accessibility_recovery_phrase_hint", defaultValue: "Enter your 12 or 24 word recovery phrase"))
                        .onChange(of: mnemonicPhrase) { oldValue, newValue in
                            // If user presses return/enter, dismiss keyboard
                            if newValue.contains("\n") || newValue.contains("\r") {
                                hideKeyboard()
                            }
                            // Remove any newlines or line breaks
                            let cleaned = newValue.replacingOccurrences(of: "\n", with: " ")
                                                   .replacingOccurrences(of: "\r", with: " ")
                            if cleaned != newValue {
                                mnemonicPhrase = cleaned
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.Arke.gold.opacity(0.2), lineWidth: 1)
                        )
                        .frame(maxWidth: 400)
                    
                    VStack(spacing: 12) {
                        Text(String(localized: "backup_file_section_title", defaultValue: "Wallet Backup File"))
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(String(localized: "backup_file_section_description", defaultValue: "Optionally add your wallet backup file to restore your transaction history and wallet data. Without it, your funds are recovered from the network, but local history is not restored."))
                            .font(.system(.body))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button {
                            showingFilePicker = true
                            
                            // Announce when file picker is opened for VoiceOver users
                            if UIAccessibility.isVoiceOverRunning {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    UIAccessibility.post(notification: .announcement, 
                                        argument: String(localized: "accessibility_file_picker_opened", defaultValue: "File picker opened. Select your backup file."))
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: backupFileURL == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if let fileName = backupFileName {
                                        Text(fileName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(String(localized: "backup_file_selected", defaultValue: "Backup file selected"))
                                            .font(.footnote)
                                            .opacity(0.8)
                                    } else {
                                        Text(String(localized: "button_select_backup_file", defaultValue: "Select Backup File"))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(String(localized: "backup_file_not_selected", defaultValue: "Optional — restore from recovery phrase only"))
                                            .font(.footnote)
                                            .opacity(0.8)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .foregroundStyle(backupFileURL == nil ? .white : Color.Arke.gold)
                            .padding(15)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        backupFileURL == nil ? 
                                            Color.Arke.gold.opacity(0.2) : 
                                            Color.Arke.gold.opacity(0.5),
                                        lineWidth: backupFileURL == nil ? 1 : 2
                                    )
                            )
                        }
                        .frame(maxWidth: 400)
                    }
                    
                    Spacer(minLength: 10)
                    
                    Button {
                        Task {
                            await importWallet()
                        }
                    } label: {
                        Text(isImporting ? String(localized: "status_importing", defaultValue: "Importing...") : L10n.buttonImportWallet)
                            .font(.system(.title2, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                    .disabled(
                        mnemonicPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        isImporting
                    )
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, safeAreaInsets.top)
                .padding(.bottom, safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.database, UTType(filenameExtension: "sqlite")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    backupFileURL = url
                    backupFileName = url.lastPathComponent
                    
                    // Announce file selection for VoiceOver users
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        UIAccessibility.post(notification: .announcement, 
                            argument: String(format: String(localized: "accessibility_backup_file_selected", defaultValue: "Selected backup file: %@"), url.lastPathComponent))
                    }
                }
            case .failure(let error):
                showError(String(format: L10n.errorFilePicker, error.localizedDescription))
            }
        }
        .alert(String(localized: "error_import", defaultValue: "Import Error"), isPresented: $showingError) {
            Button(L10n.buttonOk) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func importWallet() async {
        let trimmedMnemonic = mnemonicPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate mnemonic
        guard !trimmedMnemonic.isEmpty else {
            showError(String(localized: "error_enter_recovery_phrase", defaultValue: "Please enter a recovery phrase"))
            return
        }

        isImporting = true

        do {
            // Select network configuration based on isMainnet flag
            let networkConfig = isMainnet ? NetworkConfig.mainnet : NetworkConfig.signet

            // The backup file is optional: with one, the wallet database is
            // restored directly; without one, bark recovers funds from the
            // network via its seed-recovery scan (local history is not restored)
            let result: String
            if let backupURL = backupFileURL {
                result = try await walletManager.importWalletWithBackup(
                    mnemonic: trimmedMnemonic,
                    backupFileURL: backupURL,
                    networkConfig: networkConfig
                )
                Self.logger.info("✅ Wallet imported successfully with backup: \(result)")
            } else {
                result = try await walletManager.importWallet(
                    mnemonic: trimmedMnemonic,
                    networkConfig: networkConfig
                )
                Self.logger.info("✅ Wallet imported successfully from recovery phrase only: \(result)")
            }
            
            // Success - call the completion handler
            onWalletImported()
            
        } catch {
            isImporting = false
            showError(String(format: String(localized: "error_import_wallet", defaultValue: "Failed to import wallet: %@"), error.localizedDescription))
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
