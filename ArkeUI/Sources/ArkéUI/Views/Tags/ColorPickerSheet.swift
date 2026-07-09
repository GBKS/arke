//
//  ColorPickerSheet.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/30/25.
//

import SwiftUI

public struct ColorPickerSheet: View {
    @Binding var selectedColorHex: String
    @Environment(\.dismiss) private var dismiss
    
    private let predefinedColors = [
        "#FF6B35", "#4A90E2", "#7B68EE", "#32CD32",
        "#FFD700", "#FF69B4", "#8B4513", "#FF4444",
        "#9370DB", "#20B2AA", "#FF8C00", "#6495ED",
        "#F0E68C", "#DDA0DD", "#98FB98", "#F0A0A0",
        "#87CEEB", "#D2B48C", "#AFEEEE", "#FAFAD2"
    ]
    
    @State private var customColor: Color = .Arke.blue
    @State private var showingCustomColorPicker = false

    public init(selectedColorHex: Binding<String>) {
        self._selectedColorHex = selectedColorHex
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Predefined Colors
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(Array(predefinedColors.enumerated()), id: \.element) { index, colorHex in
                            swatchButton(index: index, colorHex: colorHex)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Custom Color Picker
                    HStack(spacing: 16) {
                        ColorPicker(String(localized: "action_choose_custom_color", bundle: .module), selection: $customColor, supportsOpacity: false)
                            .padding(.horizontal)
                            .onChange(of: customColor) { _, newColor in
                                // Commit immediately so dismissing via the
                                // checkmark doesn't discard the custom color.
                                selectedColorHex = newColor.toHex()
                            }

                        Button(action: {
                            selectedColorHex = customColor.toHex()
                            dismiss()
                        }) {
                            Label {
                                Text("button_use_custom_color", bundle: .module)
                            } icon: {
                                Image(systemName: "paintbrush")
                            }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(customColor.opacity(0.2))
                                .foregroundColor(customColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(Text("button_choose_color", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("button_done", bundle: .module))
                }
            }
        }
        .onAppear {
            if let color = Color(hex: selectedColorHex) {
                customColor = color
            }
        }
    }

    private func swatchButton(index: Int, colorHex: String) -> some View {
        let isSelected = selectedColorHex == colorHex
        let fillColor: Color = Color(hex: colorHex) ?? .Arke.blue
        let outerRing: Color = isSelected ? .systemBackground : .clear
        let innerRing: Color = isSelected ? fillColor : .clear

        return Button(action: {
            selectedColorHex = colorHex
            dismiss()
        }) {
            Circle()
                .fill(fillColor)
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(outerRing, lineWidth: 8))
                .overlay(Circle().stroke(innerRing, lineWidth: 2))
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: selectedColorHex)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("accessibility_color_swatch \(index + 1)", bundle: .module))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    ColorPickerSheet(selectedColorHex: .constant("#FF6B35"))
}
