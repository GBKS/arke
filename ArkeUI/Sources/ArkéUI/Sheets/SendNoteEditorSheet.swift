//
//  SendNoteEditorSheet.swift
//  Arké
//
//  Created for Phase 3b: Send Metadata Enhancement
//  Sheet for editing note during payment send
//

import SwiftUI

public struct SendNoteEditorSheet: View {
    @Binding var note: String
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    private let maxCharacters = 1000

    public init(note: Binding<String>, onDismiss: @escaping () -> Void) {
        self._note = note
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Character count
                HStack {
                    Spacer()
                    Text("\(note.count) / \(maxCharacters)")
                        .font(.caption)
                        .foregroundColor(note.count > maxCharacters ? .red : .secondary)
                }
                .padding(.horizontal)
                
                // Text editor
                #if os(iOS)
                TextEditor(text: $note)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                #else
                TextEditor(text: $note)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                #endif
                
                Spacer()
            }
            .navigationTitle("Add Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                    }
                    .disabled(note.count > maxCharacters)
                }
            }
            .onAppear {
                // Auto-focus the text editor when sheet appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
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
