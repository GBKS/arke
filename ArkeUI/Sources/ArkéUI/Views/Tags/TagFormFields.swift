//
//  TagFormFields.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

public struct TagFormFields: View {
    @Binding var name: String
    @Binding var selectedEmoji: String
    @Binding var selectedColorHex: String
    @Binding var showingEmojiPicker: Bool
    @Binding var showingColorPicker: Bool
    
    let nameExists: Bool
    let onSubmit: () -> Void

    public init(
        name: Binding<String>,
        selectedEmoji: Binding<String>,
        selectedColorHex: Binding<String>,
        showingEmojiPicker: Binding<Bool>,
        showingColorPicker: Binding<Bool>,
        nameExists: Bool,
        onSubmit: @escaping () -> Void
    ) {
        self._name = name
        self._selectedEmoji = selectedEmoji
        self._selectedColorHex = selectedColorHex
        self._showingEmojiPicker = showingEmojiPicker
        self._showingColorPicker = showingColorPicker
        self.nameExists = nameExists
        self.onSubmit = onSubmit
    }

    @FocusState private var isNameFieldFocused: Bool

    public var body: some View {
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
                Text("label_name", bundle: .module)
                    .font(.headline)

                Spacer()

                Text("\(name.count)/30")
                    .font(.caption)
                    .foregroundStyle(name.count > 25 ? .orange : .secondary)
                    .accessibilityHidden(true)
            }

            TextField(String(localized: "placeholder_tag_name", bundle: .module), text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isNameFieldFocused)
                .onSubmit {
                    isNameFieldFocused = false
                    onSubmit()
                }
                .accessibilityLabel(Text("label_name", bundle: .module))

            if nameExists {
                Label {
                    Text("error_tag_already_exists", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundColor(.Arke.orange)
            }
        }
    }
    
    // MARK: - Emoji Field
    
    @ViewBuilder
    private var emojiField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("label_emoji_optional", bundle: .module)
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

                        (selectedEmoji.isEmpty
                            ? Text("action_choose_emoji", bundle: .module)
                            : Text("action_change_emoji", bundle: .module))
                            .foregroundStyle(selectedEmoji.isEmpty ? .secondary : .primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("accessibility_hint_choose_emoji", bundle: .module))

                if !selectedEmoji.isEmpty {
                    Button {
                        selectedEmoji = ""
                    } label: {
                        Text("button_clear", bundle: .module)
                    }
                    .font(.caption)
                    .foregroundColor(Color.Arke.red)
                }
            }
        }
    }
    
    // MARK: - Color Field
    
    @ViewBuilder
    private var colorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("label_color", bundle: .module)
                .font(.headline)

            Button(action: {
                showingColorPicker.toggle()
            }) {
                HStack {
                    Circle()
                        .fill(Color(hex: selectedColorHex) ?? .Arke.blue)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    Text("action_choose_color", bundle: .module)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .padding()
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("accessibility_hint_choose_color", bundle: .module))
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
