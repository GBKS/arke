//
//  ImportWalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import ArkeUI

struct ImportWalletView: View {
    let isMainnet: Bool
    let onBack: () -> Void
    let onWalletImported: () -> Void

    @Environment(WalletManager.self) private var walletManager
    @State private var mnemonicPhrase: String = ""
    @State private var backupFileURL: URL?
    @State private var backupFileName: String?
    @State private var showingFilePicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isImporting = false
    
    var body: some View {
        VStack(spacing: 30) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Arke.gold)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                Text("onboarding_import_title")
                    .font(.system(size: 40, design: .serif))
                    .foregroundStyle(Color.Arke.gold)
                
                Text("onboarding_restore_wallet")
                    .fontWeight(.light)
                    .font(.system(size: 21))
                    .lineSpacing(6)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            
            TextEditor(text: $mnemonicPhrase)
                .padding(15)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.05))
                .foregroundStyle(.white)
                .font(.system(size: 21, design: .monospaced))
                .lineSpacing(4)
                .cornerRadius(8)
                .overlay(alignment: .topLeading) {
                    if mnemonicPhrase.isEmpty {
                        Text("placeholder_enter_recovery_phrase")
                            .foregroundStyle(.gray)
                            .font(.system(size: 21, design: .monospaced))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.Arke.gold.opacity(0.2), lineWidth: 1)
                )
                .frame(maxWidth: 400, minHeight: 80, maxHeight: 130)

            VStack(spacing: 12) {
                Text("backup_file_section_title")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("backup_file_section_description")
                    .fontWeight(.light)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showingFilePicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: backupFileURL == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 4) {
                            if let fileName = backupFileName {
                                Text(fileName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("backup_file_selected")
                                    .font(.footnote)
                                    .opacity(0.8)
                            } else {
                                Text("button_select_backup_file")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("backup_file_not_selected")
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
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 400)

            Spacer()

            Button(isImporting ? LocalizedStringKey("status_importing") : LocalizedStringKey("button_import_wallet")) {
                Task {
                    await importWallet()
                }
            }
            .buttonStyle(ArkeButtonStyle(size: .large, isLoading: isImporting))
            .disabled(mnemonicPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Arke.gold4)
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
                }
            case .failure(let error):
                showError(String(format: NSLocalizedString("error_file_picker", comment: ""), error.localizedDescription))
            }
        }
        .alert("error_import", isPresented: $showingError) {
            Button("button_ok") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func importWallet() async {
        let trimmedMnemonic = mnemonicPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation
        guard !trimmedMnemonic.isEmpty else {
            showError(NSLocalizedString("error_enter_recovery_phrase", comment: ""))
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
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
                print("✅ Wallet imported successfully with backup: \(result)")
            } else {
                result = try await walletManager.importWallet(
                    mnemonic: trimmedMnemonic,
                    networkConfig: networkConfig
                )
                print("✅ Wallet imported successfully from recovery phrase only: \(result)")
            }

            // Success - call the completion handler
            onWalletImported()

        } catch {
            showError(String(format: NSLocalizedString("error_import_wallet", comment: ""), error.localizedDescription))
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
