//
//  DataView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum VTXOError: Error, LocalizedError {
    case walletNotAvailable
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .walletNotAvailable:
            return "Wallet not available"
        case .parsingFailed:
            return "Failed to parse VTXO data"
        }
    }
}

struct DataView: View {
    @Binding var selectedDataItem: DataDetailItem?
    @Environment(WalletManager.self) private var walletManager
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showingExportSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                ArkBalanceView()
                
                OnchainBalanceView()
                
                VTXOListView(selectedDataItem: $selectedDataItem)
                
                UTXOListView(selectedDataItem: $selectedDataItem)
                
                ConfigurationSectionView()
                
                ArkInfoSectionView()
                
                BlockHeightSectionView()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 30)
            .navigationTitle("Your wallet in-depth")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await exportWalletData()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("Download")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") {
                    exportError = nil
                }
            } message: {
                Text(exportError ?? "")
            }
            .alert("Export Successful", isPresented: $showingExportSuccess) {
                Button("OK") { }
            } message: {
                Text("Wallet data has been saved successfully.")
            }
        }
    }
    
    @MainActor
    private func exportWalletData() async {
        isExporting = true
        defer { isExporting = false }
        
        do {
            let jsonData = try await walletManager.exportWalletData()
            
            let savePanel = NSSavePanel()
            savePanel.title = "Export Wallet Data"
            savePanel.nameFieldStringValue = "wallet-data-\(DateFormatter.filenameDateFormatter.string(from: Date())).json"
            savePanel.allowedContentTypes = [.json]
            savePanel.canCreateDirectories = true
            
            let response = savePanel.runModal()
            
            if response == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
                showingExportSuccess = true
            }
        } catch {
            exportError = "Failed to export wallet data: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        DataView(selectedDataItem: .constant(nil))
            .environment(WalletManager(useMock: true))
    }
    .frame(width: 400, height: 800)
}

// MARK: - Extensions
extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}
