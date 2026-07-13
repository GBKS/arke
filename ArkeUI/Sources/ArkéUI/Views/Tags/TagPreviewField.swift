//
//  TagPreviewField.swift
//  ArkéUI
//
//  Created by Assistant on 7/9/26.
//

import SwiftUI

/// The large editable tag preview shown at the top of the tag editor.
///
/// A capsule tinted in the selected color with three tap targets:
/// a circular emoji button on the left, the tag name text field in the
/// center, and a solid color circle on the right. The emoji and color
/// buttons report taps; the owner decides which inline picker to
/// reveal and passes it back via `activePicker` so the corresponding
/// button can render its selected ring. Focus is owned by the caller
/// so it can coordinate the keyboard with the pickers.
public struct TagPreviewField: View {
    /// Which inline picker the owner currently has revealed (nil = none).
    public enum ActivePicker {
        case emoji
        case color
    }

    @Binding var name: String
    @Binding var selectedEmoji: String
    @Binding var selectedColorHex: String
    var isNameFocused: FocusState<Bool>.Binding
    let activePicker: ActivePicker?
    let maxLength: Int

    let onTapEmoji: () -> Void
    let onTapColor: () -> Void
    let onSubmit: () -> Void

    public init(
        name: Binding<String>,
        selectedEmoji: Binding<String>,
        selectedColorHex: Binding<String>,
        isNameFocused: FocusState<Bool>.Binding,
        activePicker: ActivePicker? = nil,
        maxLength: Int = 30,
        onTapEmoji: @escaping () -> Void,
        onTapColor: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self._name = name
        self._selectedEmoji = selectedEmoji
        self._selectedColorHex = selectedColorHex
        self.isNameFocused = isNameFocused
        self.activePicker = activePicker
        self.maxLength = maxLength
        self.onTapEmoji = onTapEmoji
        self.onTapColor = onTapColor
        self.onSubmit = onSubmit
    }

    private var tint: Color {
        Color(hex: selectedColorHex) ?? .Arke.blue
    }

    public var body: some View {
        HStack(spacing: 12) {
            emojiButton
            nameField
            colorButton
        }
        .padding(8)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: selectedColorHex)
        .animation(.easeInOut(duration: 0.2), value: activePicker)
    }

    /// Ring drawn around a picker button while its picker is revealed.
    @ViewBuilder
    private func activeRing(_ picker: ActivePicker) -> some View {
        Circle()
            .stroke(tint, lineWidth: 2)
            .padding(-4)
            .opacity(activePicker == picker ? 1 : 0)
    }

    // MARK: - Emoji Button

    @ViewBuilder
    private var emojiButton: some View {
        Button(action: onTapEmoji) {
            Circle()
                .fill(tint.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    if selectedEmoji.isEmpty {
                        Image(systemName: "face.smiling")
                            .font(.title3)
                            .foregroundStyle(tint)
                    } else {
                        Text(selectedEmoji)
                            .font(.title3)
                    }
                }
                .overlay(activeRing(.emoji))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            selectedEmoji.isEmpty
                ? Text("action_choose_emoji", bundle: .module)
                : Text("action_change_emoji", bundle: .module)
        )
        .accessibilityHint(Text("accessibility_hint_choose_emoji", bundle: .module))
        .accessibilityAddTraits(activePicker == .emoji ? .isSelected : [])
    }

    // MARK: - Name Field

    @ViewBuilder
    private var nameField: some View {
        // A TextField greedily fills all offered width, which would force
        // the capsule to full width. Instead, invisible text mirrors
        // whichever is wider — the placeholder or the current name — so
        // the capsule starts placeholder-sized and only grows once the
        // name outgrows it. The real field is overlaid at that size.
        ZStack {
            Text("placeholder_tag_name", bundle: .module)
            Text(verbatim: name)
        }
        .font(.title3)
        .fontWeight(.medium)
        .lineLimit(1)
        .opacity(0)
        .accessibilityHidden(true)
        .overlay {
            TextField(String(), text: $name)
                .textFieldStyle(.plain)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(tint)
                .tint(tint)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused(isNameFocused)
                .onSubmit(onSubmit)
                .onChange(of: name) { _, newValue in
                    if newValue.count > maxLength {
                        name = String(newValue.prefix(maxLength))
                    }
                }
                .overlay(alignment: .leading) {
                    // Custom placeholder so it renders in the tag color.
                    if name.isEmpty {
                        Text("placeholder_tag_name", bundle: .module)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(tint.opacity(0.6))
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(Text("label_name", bundle: .module))
        }
    }

    // MARK: - Color Button

    @ViewBuilder
    private var colorButton: some View {
        Button(action: onTapColor) {
            Circle()
                .fill(tint)
                .frame(width: 40, height: 40)
                .overlay(activeRing(.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("action_choose_color", bundle: .module))
        .accessibilityHint(Text("accessibility_hint_choose_color", bundle: .module))
        .accessibilityAddTraits(activePicker == .color ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var name = ""
    @Previewable @State var emoji = "👜"
    @Previewable @State var colorHex = "#DC8228"
    @Previewable @FocusState var isNameFocused: Bool

    VStack(spacing: 24) {
        TagPreviewField(
            name: $name,
            selectedEmoji: $emoji,
            selectedColorHex: $colorHex,
            isNameFocused: $isNameFocused,
            onTapEmoji: { print("Emoji tapped") },
            onTapColor: { print("Color tapped") },
            onSubmit: { print("Submit") }
        )

        TagPreviewField(
            name: .constant("Groceries"),
            selectedEmoji: .constant("🛒"),
            selectedColorHex: .constant("#288C82"),
            isNameFocused: $isNameFocused,
            activePicker: .emoji,
            onTapEmoji: {},
            onTapColor: {},
            onSubmit: {}
        )

        TagPreviewField(
            name: .constant("Travel"),
            selectedEmoji: .constant("✈️"),
            selectedColorHex: .constant("#7B68EE"),
            isNameFocused: $isNameFocused,
            activePicker: .color,
            onTapEmoji: {},
            onTapColor: {},
            onSubmit: {}
        )
    }
    .padding()
}
