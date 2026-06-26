//
//  SendNoteEditorSheet.swift
//  Arké
//
//  Created for Phase 3b: Send Metadata Enhancement
//  Sheet for editing note during payment send
//

import SwiftUI
import ArkeUI

public struct SendNoteEditorSheet: View {
    @Binding var note: String
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    private let maxCharacters = 500

    public init(note: Binding<String>, onDismiss: @escaping () -> Void) {
        self._note = note
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and cancel button
            HStack(spacing: 10) {
                // Text field
                TextField("Add a note...", text: $note, axis: .vertical)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    #if os(iOS)
                    .background(Color(.systemGray5))
                    #else
                    .background(Color(nsColor: .controlBackgroundColor))
                    #endif
                    .cornerRadius(15)
                    .lineLimit(1...5)
                
                // Done button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.title2)
                        .foregroundStyle(Color.Arke.gold4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                .accessibilityLabel("button_done")
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical)
        #if os(iOS)
        .presentationDetents([.height(150)])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            // Auto-focus the text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

#Preview("Empty Note") {
    @Previewable @State var note = ""
    
    SendNoteEditorSheet(
        note: $note,
        onDismiss: { print("Dismissed") }
    )
}

#Preview("With Note") {
    @Previewable @State var note = "Coffee at the cafe"
    
    SendNoteEditorSheet(
        note: $note,
        onDismiss: { print("Dismissed") }
    )
}

#Preview("Long Note") {
    @Previewable @State var note = String(repeating: "This is a test note. ", count: 20)
    
    SendNoteEditorSheet(
        note: $note,
        onDismiss: { print("Dismissed") }
    )
}
