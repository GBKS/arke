//
//  RecoveryPhraseSettingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct RecoveryPhraseSettingView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var mnemonic: String = ""
    @State private var isLoadingMnemonic = false
    @State private var showMnemonic = false
    @State private var errorMessage: String?
    @State private var showCopiedFeedback = false
    @State private var showingQRCode = false
    @State private var revealAllWords = false
    @State private var showingShareSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings_recovery_phrase_help", defaultValue: "Your recovery phrase restores your wallet. Anyone who has it can spend your bitcoin. Keep it safe and never share it."))
                .font(.title3)
                .foregroundColor(.secondary)
                .lineSpacing(6)
            
            if showMnemonic {
                if isLoadingMnemonic {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(localized: "progress_loading", defaultValue: "Loading..."))
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if !mnemonic.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        #if os(iOS)
                        /*
                        Text("Scratch to reveal.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        */
                        
                        ScratchableMnemonicGrid_iOS(
                            mnemonic: mnemonic,
                            revealAll: $revealAllWords
                        )
                        #else
                        MnemonicGrid(mnemonic: mnemonic)
                        #endif
                        
                        HStack(spacing: 15) {
                            #if os(iOS)
                            if !revealAllWords {
                                Button {
                                    revealAllWords = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "eye")
                                            .frame(width: 24, height: 24)
                                            .foregroundStyle(Color.Arke.gold2)
                                        //Text(String(localized: "button_reveal_words", defaultValue: "Reveal All Words"))
                                        //    .foregroundStyle(Color.Arke.gold2)
                                    }
                                }
                                .accessibilityLabel(String(localized: "button_reveal_words", defaultValue: "Reveal All Words"))
                                .buttonStyle(.glass)
                                .controlSize(.regular)
                                .tint(Color.Arke.gold)
                            }
                            #endif
                            
                            Button(action: {
                                copyToClipboard(mnemonic)
                                showCopiedFeedback = true
                                
                                // Hide feedback after 2 seconds
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    await MainActor.run {
                                        showCopiedFeedback = false
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if showCopiedFeedback {
                                        Image(systemName: "checkmark.circle.fill")
                                            .frame(width: 24, height: 24)
                                            .foregroundColor(.Arke.green)
                                            .transition(.scale.combined(with: .opacity))
                                    } else {
                                        Image(systemName: "doc.on.clipboard")
                                            .frame(width: 24, height: 24)
                                            .foregroundStyle(Color.Arke.gold2)
                                    }
                                    
                                    //Text(showCopiedFeedback ? L10n.statusCopiedExclaim : String(localized: "button_copy_clipboard", defaultValue: "Copy to Clipboard"))
                                    //    .foregroundColor(showCopiedFeedback ? .Arke.green : .Arke.gold2)
                                }
                            }
                            .accessibilityLabel(showCopiedFeedback ? L10n.statusCopiedExclaim : String(localized: "button_copy_clipboard", defaultValue: "Copy to Clipboard"))
                            .buttonStyle(.glass)
                            .controlSize(.regular)
                            .tint(Color.Arke.gold)
                            .animation(.easeInOut(duration: 0.3), value: showCopiedFeedback)
                            
                            Button(action: {
                                showingQRCode = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "qrcode")
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(Color.Arke.gold2)
                                    //Text(String(localized: "action_show_qr", defaultValue: "Show as QR Code"))
                                    //    .foregroundStyle(Color.Arke.gold2)
                                }
                            }
                            .accessibilityLabel(String(localized: "action_show_qr", defaultValue: "Show as QR Code"))
                            .buttonStyle(.glass)
                            .controlSize(.regular)
                            .tint(Color.Arke.gold)
                        }
                        
                        Divider()
                        
                        // Backup Sheet Download Card
                        #if os(macOS)
                        if let pdfURL = Bundle.main.url(forResource: "arke-recovery-phrase-backup-sheet", withExtension: "pdf") {
                            Link(destination: pdfURL) {
                                backupSheetCard
                            }
                        }
                        #else
                        Button(action: {
                            downloadBackupSheet()
                        }) {
                            backupSheetCard
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                    .padding(.top, 15)
                } else if let error = errorMessage {
                    ErrorBox(errorMessage: error)
                }
            } else {
                #if os(iOS)
                // On iOS, show scratchable mnemonic immediately
                #else
                Button {
                    Task {
                        await loadMnemonic()
                    }
                } label: {
                    Text(String(localized: "settings_show_recovery_phrase", defaultValue: "Show Recovery Phrase"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(Color.Arke.gold)
                .padding(.top, 15)
                #endif
            }
            
            
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(String(localized: "settings_recovery_phrase", defaultValue: "Recovery Phrase"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .task {
            // On iOS, load mnemonic automatically for scratchable view
            if mnemonic.isEmpty {
                await loadMnemonic()
            }
        }
        #endif
        .onDisappear {
            // Reset scratch state when navigating away
            revealAllWords = false
        }
        .sheet(isPresented: $showingQRCode) {
            qrCodeSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #if os(iOS)
        .sheet(isPresented: $showingShareSheet) {
            if let pdfURL = Bundle.main.url(forResource: "arke-recovery-phrase-backup-sheet", withExtension: "pdf") {
                ShareSheet(items: [pdfURL])
            }
        }
        #endif
    }
    
    @ViewBuilder
    private var qrCodeSheet: some View {
        if !mnemonic.isEmpty {
            ArkeQRCodeView(
                content: mnemonic,
                title: "Recovery Phrase",
                onClose: { showingQRCode = false }
            )
            #if os(macOS)
            .frame(minWidth: 300, minHeight: 300)
            #endif
        }
    }
    
    @ViewBuilder
    private var backupSheetCard: some View {
        HStack(spacing: 12) {
            Image("arke-recovery-phrase-backup-sheet")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 53, height: 75)
                .cornerRadius(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "action_download_backup", defaultValue: "Download backup sheet"))
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                
                Text(String(localized: "settings_backup_print", defaultValue: "Print and write your phrase"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func loadMnemonic() async {
        isLoadingMnemonic = true
        errorMessage = nil
        
        do {
            let recoveryPhrase = try await walletManager.getMnemonic()
            await MainActor.run {
                mnemonic = recoveryPhrase
                showMnemonic = true
                isLoadingMnemonic = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingMnemonic = false
            }
        }
    }
    
    #if os(iOS)
    private func downloadBackupSheet() {
        showingShareSheet = true
    }
    #endif
}

// MARK: - Mnemonic Grid (Shared)

struct MnemonicGrid: View {
    let mnemonic: String
    let cornerRadius: CGFloat = 12.0
    
    var body: some View {
        let words = mnemonic.components(separatedBy: " ")
        let halfCount = (words.count + 1) / 2
        let firstHalf = Array(words.prefix(halfCount))
        let secondHalf = Array(words.suffix(words.count - halfCount))
        
        HStack(alignment: .top, spacing: 8) {
            // First column
            VStack(spacing: 8) {
                ForEach(Array(firstHalf.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Text("\(index + 1)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        Text(word)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(.background)
                    .cornerRadius(100)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .systemGray6))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
            // Second column
            VStack(spacing: 8) {
                ForEach(Array(secondHalf.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Text("\(halfCount + index + 1)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        Text(word)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(.background)
                    .cornerRadius(100)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .systemGray6))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
