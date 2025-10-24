//
//  SettingsView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var mnemonic: String = ""
    @State private var isLoadingMnemonic = false
    @State private var showMnemonic = false
    @State private var errorMessage: String?
    @State private var showCopiedFeedback = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // Recovery Phrase Section
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery Phrase")
                        .font(.system(size: 24, design: .serif))
                    
                    Text("Your recovery phrase is used to restore your wallet. Keep it safe and never share it.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    if showMnemonic {
                        if isLoadingMnemonic {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        } else if !mnemonic.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                    ForEach(Array(mnemonic.components(separatedBy: " ").enumerated()), id: \.offset) { index, word in
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
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(100)
                                    }
                                }
                                
                                Button(action: {
                                    NSPasteboard.general.setString(mnemonic, forType: .string)
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
                                                .foregroundColor(.black)
                                                .transition(.scale.combined(with: .opacity))
                                        } else {
                                            Image(systemName: "doc.on.clipboard")
                                        }
                                        
                                        Text(showCopiedFeedback ? "Copied!" : "Copy to Clipboard")
                                    }
                                }
                                .buttonStyle(ArkeButtonStyle(size: .small))
                                .animation(.easeInOut(duration: 0.3), value: showCopiedFeedback)
                            }
                            .padding(.top, 15)
                        } else if let error = errorMessage {
                            Text("Error: \(error)")
                                .font(.body)
                                .foregroundColor(.red)
                                .padding()
                        }                        
                    } else {
                        Button("Show Recovery Phrase") {
                            Task {
                                await loadMnemonic()
                            }
                        }
                        .buttonStyle(ArkeButtonStyle(size: .small))
                        .padding(.top, 15)
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 20) {
                // Recovery Phrase Section
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delete wallet")
                        .font(.system(size: 24, design: .serif))
                    
                    Text("Not implemented yet.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Settings")
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
}

#Preview {
    SettingsView()
        .environment(WalletManager(useMock: true))
}
