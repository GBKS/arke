//
//  TagFormFields.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

struct TagFormFields: View {
    @Binding var name: String
    @Binding var selectedEmoji: String
    @Binding var selectedColorHex: String
    @Binding var showingEmojiPicker: Bool
    @Binding var showingColorPicker: Bool
    
    let nameExists: Bool
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Name Field
            nameField
            
            // Emoji Field
            emojiField
            
            // Color Field
            colorField
        }
        .animation(.easeInOut(duration: 0.2), value: nameExists)
    }
    
    // MARK: - Name Field
    
    @ViewBuilder
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Name")
                    .font(.headline)
                
                Spacer()
                
                Text("\(name.count)/30")
                    .font(.caption)
                    .foregroundStyle(name.count > 25 ? .orange : .secondary)
            }
            
            TextField("Enter tag name", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            
            if nameExists {
                Label("A tag with this name already exists", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Emoji Field
    
    @ViewBuilder
    private var emojiField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emoji (Optional)")
                .font(.headline)
            
            HStack {
                Button(action: {
                    showingEmojiPicker.toggle()
                }) {
                    HStack {
                        if selectedEmoji.isEmpty {
                            Image(systemName: "face.smiling")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(selectedEmoji)
                                .font(.title2)
                        }
                        
                        Text(selectedEmoji.isEmpty ? "Choose emoji" : "Change emoji")
                            .foregroundStyle(selectedEmoji.isEmpty ? .secondary : .primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                if !selectedEmoji.isEmpty {
                    Button("Clear") {
                        selectedEmoji = ""
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Color Field
    
    @ViewBuilder
    private var colorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.headline)
            
            Button(action: {
                showingColorPicker.toggle()
            }) {
                HStack {
                    Circle()
                        .fill(Color(hex: selectedColorHex) ?? .blue)
                        .frame(width: 24, height: 24)
                    
                    Text("Choose color")
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    TagFormFields(
        name: .constant("Coffee"),
        selectedEmoji: .constant("☕"),
        selectedColorHex: .constant("#8B4513"),
        showingEmojiPicker: .constant(false),
        showingColorPicker: .constant(false),
        nameExists: false,
        onSubmit: { print("Submit") }
    )
    .padding()
}