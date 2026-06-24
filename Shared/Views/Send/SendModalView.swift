//
//  SendModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import ArkeUI

struct SendModalView: View {
    let onDismissEntireView: (() -> Void)?
    let performSend: () async throws -> Void
    @Binding var pendingMetadata: PendingPaymentMetadata?
    
    @Environment(\.dismiss) private var dismiss
    @State private var state: SendModalState = .sending
    @State private var sendStartTime: Date?
    
    private let minimumSendingDuration: TimeInterval = 0.8 // 800ms minimum
    
    var body: some View {
        SendModalContentView(
            state: state,
            pendingMetadata: $pendingMetadata,
            onDismiss: {
                print("✅ [SendModalView] \(state) - dismissing")
                dismiss()
            },
            onDismissEntireView: state == .success ? onDismissEntireView : nil
        )
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        ))
        .animation(.easeInOut(duration: 0.3), value: state)
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await executeSend()
        }
    }
    
    @MainActor
    private func executeSend() async {
        sendStartTime = Date()
        
        do {
            try await performSend()
            
            // Ensure minimum display time for "sending" state
            await enforceMinimumSendingDuration()
            
            state = .success
        } catch {
            // Ensure minimum display time for "sending" state
            await enforceMinimumSendingDuration()
            
            state = .error(error.localizedDescription)
        }
    }
    
    @MainActor
    private func enforceMinimumSendingDuration() async {
        guard let startTime = sendStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = minimumSendingDuration - elapsed
        
        if remaining > 0 {
            try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
        }
    }
}
