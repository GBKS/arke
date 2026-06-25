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
                        ForEach(predefinedColors, id: \.self) { colorHex in
                            Button(action: {
                                selectedColorHex = colorHex
                                dismiss()
                            }) {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? .Arke.blue)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                selectedColorHex == colorHex ? Color.primary : Color.clear,
                                                lineWidth: 3
                                            )
                                    )
                                    .scaleEffect(selectedColorHex == colorHex ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.3), value: selectedColorHex)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Custom Color Picker
                    HStack(spacing: 16) {
                        ColorPicker(String(localized: "action_choose_custom_color"), selection: $customColor, supportsOpacity: false)
                            .padding(.horizontal)
                        
                        Button(action: {
                            selectedColorHex = customColor.toHex()
                            dismiss()
                        }) {
                            Label("button_use_custom_color", systemImage: "paintbrush")
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
            .navigationTitle("button_choose_color")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("button_done")
                }
            }
        }
        .onAppear {
            if let color = Color(hex: selectedColorHex) {
                customColor = color
            }
        }
    }
}

#Preview {
    ColorPickerSheet(selectedColorHex: .constant("#FF6B35"))
}
