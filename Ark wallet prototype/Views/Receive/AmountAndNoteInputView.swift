//
//  AmountAndNoteInputView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import SwiftUI

struct AmountAndNoteInputView: View {
    @Binding var amount: String
    @Binding var note: String
    @Binding var showingAmountAndNote: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if !showingAmountAndNote {
                amountAndNoteToggleButton
            } else {
                amountAndNoteInputView
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    @ViewBuilder
    private var amountAndNoteToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingAmountAndNote = true
            }
        } label: {
            HStack(spacing: 6) {
                Text("Add amount and note")
                    .font(.body)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var amountAndNoteInputView: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                amountInputField
                Divider()
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                noteInputField
            }
            .background(.regularMaterial)
            .cornerRadius(8)
        }
        .frame(maxWidth: 400)
    }
    
    @ViewBuilder
    private var amountInputField: some View {
        HStack(spacing: 8) {
            TextField("Add amount (in sats)", text: $amount)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.leading, 16)
                .padding(.vertical, 12)
            Spacer()
            Text("₿")
                .font(.system(.body, design: .monospaced))
                .padding(.trailing, 16)
        }
    }
    
    @ViewBuilder
    private var noteInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add note (optional)", text: $note)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }
}

#Preview {
    @Previewable @State var amount = ""
    @Previewable @State var note = ""
    @Previewable @State var showingAmountAndNote = false
    
    AmountAndNoteInputView(
        amount: $amount,
        note: $note,
        showingAmountAndNote: $showingAmountAndNote
    )
    .padding()
    .frame(width: 400, height: 200)
}
