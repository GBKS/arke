//
//  TransactionNotesSection.swift
//  Arké
//
//  Created by Christoph on 11/16/25.
//

import SwiftUI
import ArkeUI

struct TransactionNotesSection: View {
    let transaction: TransactionModel
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var notesText: String = ""
    @State private var currentTransactionId: String = ""
    @State private var lastSavedText: String = ""
    @FocusState private var isNotesFocused: Bool
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var saveTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "placeholder_add_note"), text: $notesText, axis: .vertical)
                .lineLimit(1...10)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Color.systemControlBackground)
                .cornerRadius(15)
                .focused($isNotesFocused)
            
            // Character counter
            /*
            HStack {
                Spacer()
                Text("\(notesText.count)/1000 characters")
                    .font(.caption)
                    .foregroundColor(characterCountColor)
            }
            */
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isNotesFocused {
                isNotesFocused = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button_done") {
                    isNotesFocused = false
                }
            }
        }
        .onAppear {
            notesText = transaction.notes ?? ""
            currentTransactionId = transaction.txid
            lastSavedText = transaction.notes ?? ""
        }
        .onChange(of: transaction.id) { oldValue, newValue in
            // Cancel any pending save
            saveTask?.cancel()
            
            // Save the previous transaction's notes immediately before loading new one
            Task {
                await saveNotesImmediately(for: currentTransactionId)
            }
            
            // Load the new transaction's notes
            notesText = transaction.notes ?? ""
            currentTransactionId = transaction.txid
            lastSavedText = transaction.notes ?? ""
            isNotesFocused = false
        }
        .onChange(of: notesText) { oldValue, newValue in
            // Debounced auto-save while typing
            debouncedSave()
        }
        .onChange(of: isNotesFocused) { oldValue, newValue in
            if oldValue == true && newValue == false {
                // Lost focus - save immediately if changed
                saveTask?.cancel()
                Task {
                    await saveNotesImmediately(for: currentTransactionId)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Save when app is backgrounding
            if newPhase == .background || newPhase == .inactive {
                saveTask?.cancel()
                Task {
                    await saveNotesImmediately(for: currentTransactionId)
                }
            }
        }
        .onDisappear {
            // Save when view is removed
            saveTask?.cancel()
            Task {
                await saveNotesImmediately(for: currentTransactionId)
            }
        }
        .alert("error_save_notes", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var characterCountColor: Color {
        let count = notesText.count
        if count > 1000 {
            return .Arke.red
        } else if count > 900 {
            return .Arke.orange
        } else {
            return .secondary
        }
    }
    
    /// Debounced save - waits 800ms after user stops typing
    private func debouncedSave() {
        // Cancel any existing save task
        saveTask?.cancel()
        
        // Create new save task with delay
        saveTask = Task {
            // Wait for 800ms
            try? await Task.sleep(for: .milliseconds(800))
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Save the notes
            await saveNotesImmediately(for: currentTransactionId)
        }
    }
    
    /// Immediately saves notes if they've changed
    private func saveNotesImmediately(for txid: String) async {
        let trimmedText = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only save if there are actual changes from what was last saved
        guard trimmedText != lastSavedText else { return }
        
        do {
            let finalNotes = trimmedText.isEmpty ? nil : trimmedText
            
            try await walletManager.updateTransactionNotes(for: txid, notes: finalNotes)
            
            // Update the last saved text to prevent duplicate saves
            lastSavedText = trimmedText
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Transaction Notes - Empty") {
    TransactionNotesSection(transaction: TransactionModel(
        txid: "abc123def456",
        movementId: 1,
        type: .sent,
        amount: 50000,
        date: Date(),
        status: .confirmed,
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        notes: nil
    ))
    .environment(WalletManager(useMock: true))
    .padding()
    .frame(width: 400)
}

#Preview("Transaction Notes - With Text") {
    TransactionNotesSection(transaction: TransactionModel(
        txid: "xyz789uvw012",
        movementId: 2,
        type: .received,
        amount: 100000,
        date: Date(),
        status: .confirmed,
        address: nil,
        notes: "Payment for consulting services rendered in October. Client confirmed receipt and will send follow-up payment next month."
    ))
    .environment(WalletManager(useMock: true))
    .padding()
    .frame(width: 400)
}

#Preview("Transaction Notes - Long Text") {
    TransactionNotesSection(transaction: TransactionModel(
        txid: "long123text456",
        movementId: 3,
        type: .sent,
        amount: 250000,
        date: Date(),
        status: .confirmed,
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        notes: String(repeating: "This is a sample note with quite a bit of text to demonstrate the character counter behavior. ", count: 10)
    ))
    .environment(WalletManager(useMock: true))
    .padding()
    .frame(width: 400)
}
