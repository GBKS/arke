//
//  ColorPickerGrid.swift
//  ArkéUI
//
//  Created by Assistant on 7/9/26.
//  Inline replacement for the former ColorPickerSheet.
//

import SwiftUI

/// Inline color picker shown below the tag preview in the tag editor.
/// Selecting a swatch updates the binding but keeps the grid open. The
/// last cell opens the system color picker for a custom color.
public struct ColorPickerGrid: View {
    @Binding var selectedColorHex: String

    @State private var customColor: Color = .Arke.blue

    // Ordered for the 5-column grid (19 swatches + custom color cell =
    // 4 clean rows): warm hues, greens and blues, violets and pinks,
    // then earth tones and neutrals. All colors sit in the same
    // mid-tone range as the system tag colors so they stay readable
    // when used as a text color (the tag preview renders the name in
    // the selected color).
    private let predefinedColors = [
        "#C33C2D", "#CF5C33", "#DC8228", "#D2AF1E", "#8FA32E",
        "#2FA854", "#288C82", "#2B98A8", "#2A7FAF", "#3E63B8",
        "#4B50A0", "#6E468C", "#9A4C96", "#BE5069", "#C86B85",
        "#8B5E3C", "#A08052", "#5E718B", "#6F6F6F"
    ]

    public init(selectedColorHex: Binding<String>) {
        self._selectedColorHex = selectedColorHex
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
            ForEach(Array(predefinedColors.enumerated()), id: \.element) { index, colorHex in
                swatchButton(index: index, colorHex: colorHex)
            }

            customColorCell
        }
        .padding()
        .background(Color.systemControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .onAppear {
            if let color = Color(hex: selectedColorHex) {
                customColor = color
            }
        }
    }

    private func swatchButton(index: Int, colorHex: String) -> some View {
        let isSelected = selectedColorHex == colorHex
        let fillColor: Color = Color(hex: colorHex) ?? .Arke.blue

        return Button(action: {
            selectedColorHex = colorHex
        }) {
            swatchCircle(fillColor: fillColor, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("accessibility_color_swatch \(index + 1)", bundle: .module))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Custom Color

    /// True when the current selection is not one of the predefined
    /// swatches, i.e. it came from the system color picker.
    private var isCustomColorSelected: Bool {
        !predefinedColors.contains(selectedColorHex)
    }

    @ViewBuilder
    private var customColorCell: some View {
        // The native color well is shown directly as the cell: hiding it
        // behind a custom swatch with a near-zero opacity puts it below
        // the hit-testing threshold, so taps never reach it. The well is
        // also the only way SwiftUI can open the system color picker.
        ColorPicker(
            String(localized: "action_choose_custom_color", bundle: .module),
            selection: $customColor,
            supportsOpacity: false
        )
        .labelsHidden()
        // The well's intrinsic size is ~32pt; scale it up to match the
        // 50pt swatches. The transform scales its tap area with it.
        .scaleEffect(50.0 / 32.0)
        .frame(width: 50, height: 50)
        .overlay {
            if isCustomColorSelected {
                Circle()
                    .stroke(Color(hex: selectedColorHex) ?? .Arke.blue, lineWidth: 2)
            }
        }
        .scaleEffect(isCustomColorSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: selectedColorHex)
        .onChange(of: customColor) { _, newColor in
            selectedColorHex = newColor.toHex()
        }
    }

    // MARK: - Swatch Rendering

    private func swatchCircle(fillColor: Color, isSelected: Bool) -> some View {
        // The 8pt ring in the card's background color creates a gap
        // between the swatch and its colored selection ring.
        let gapRing: Color = isSelected ? .systemControlBackground : .clear
        let selectionRing: Color = isSelected ? fillColor : .clear

        return Circle()
            .fill(fillColor)
            .frame(width: 50, height: 50)
            .overlay(Circle().stroke(gapRing, lineWidth: 8))
            .overlay(Circle().stroke(selectionRing, lineWidth: 2))
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: selectedColorHex)
    }
}

#Preview {
    @Previewable @State var selectedColorHex = "#2A7FAF"

    ColorPickerGrid(selectedColorHex: $selectedColorHex)
        .padding()
}
