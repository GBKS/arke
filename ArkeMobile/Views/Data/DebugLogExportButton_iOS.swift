//
//  DebugLogExportButton_iOS.swift
//  Arké
//
//  Generates a debug log file and hands it to the share sheet.
//  Lives at the bottom of the X-ray view.
//

import SwiftUI
import ArkeUI

struct DebugLogExportButton_iOS: View {
    @Environment(WalletManager.self) private var manager

    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Button(action: generateAndShare) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .tint(Color.Arke.gold4)
                } else {
                    Image(systemName: "waveform.path.ecg")
                }
                Text(isGenerating ? "debug_logs_generating" : "debug_logs_title")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.vertical, 4)
            .foregroundStyle(Color.Arke.gold4)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.regular)
        .tint(Color.Arke.gold)
        .disabled(isGenerating)
        .padding(.horizontal)
        .padding(.bottom, 20)
        .alert("debug_logs_error_title", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func generateAndShare() {
        guard !isGenerating else { return }
        isGenerating = true

        Task {
            do {
                let url = try await DebugLogExporter.generateLogFile(contextLines: contextLines)
                await MainActor.run {
                    isGenerating = false
                    ShareHelper.share(items: [url])
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    /// Non-secret context appended to the log header to help diagnosis.
    private var contextLines: [String] {
        var lines = ["Wallet mode: \(manager.isReadOnlyMode ? "read-only" : "primary")"]
        if let network = manager.networkConfig {
            lines.append("Network: \(network.name)")
        }
        return lines
    }
}
