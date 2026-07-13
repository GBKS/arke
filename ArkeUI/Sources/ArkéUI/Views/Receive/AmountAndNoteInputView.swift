//
//  AmountAndNoteInputView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import SwiftUI

public struct AmountAndNoteInputView: View {
    @Binding var amount: String
    @Binding var note: String
    @Binding var showingAmountAndNote: Bool
    
    var amountPlaceholder: String = String(localized: "placeholder_amount_optional", bundle: .module)
    var notePlaceholder: String = String(localized: "placeholder_note_optional", bundle: .module)
    var unitLabel: String? = nil
    var isDisabled: Bool = false
    var allowDecimal: Bool = true
    #if os(iOS)
    var keyboardType: UIKeyboardType = .decimalPad
    #endif
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case amount
        case note
    }

    /// VoiceOver label for the amount field, including the unit when present.
    private var amountAccessibilityLabel: String {
        if let unit = unitLabel {
            return String(localized: "accessibility_amount_label_with_unit \(unit)", bundle: .module)
        } else {
            return String(localized: "accessibility_amount_label", bundle: .module)
        }
    }

    #if os(iOS)
    public init(
        amount: Binding<String>,
        note: Binding<String>,
        showingAmountAndNote: Binding<Bool>,
        amountPlaceholder: String? = nil,
        notePlaceholder: String? = nil,
        unitLabel: String? = nil,
        isDisabled: Bool = false,
        allowDecimal: Bool = true,
        keyboardType: UIKeyboardType = .decimalPad
    ) {
        self._amount = amount
        self._note = note
        self._showingAmountAndNote = showingAmountAndNote
        self.amountPlaceholder = amountPlaceholder ?? String(localized: "placeholder_amount_optional", bundle: .module)
        self.notePlaceholder = notePlaceholder ?? String(localized: "placeholder_note_optional", bundle: .module)
        self.unitLabel = unitLabel
        self.isDisabled = isDisabled
        self.allowDecimal = allowDecimal
        self.keyboardType = keyboardType
    }
    #else
    public init(
        amount: Binding<String>,
        note: Binding<String>,
        showingAmountAndNote: Binding<Bool>,
        amountPlaceholder: String? = nil,
        notePlaceholder: String? = nil,
        unitLabel: String? = nil,
        isDisabled: Bool = false,
        allowDecimal: Bool = true
    ) {
        self._amount = amount
        self._note = note
        self._showingAmountAndNote = showingAmountAndNote
        self.amountPlaceholder = amountPlaceholder ?? String(localized: "placeholder_amount_optional", bundle: .module)
        self.notePlaceholder = notePlaceholder ?? String(localized: "placeholder_note_optional", bundle: .module)
        self.unitLabel = unitLabel
        self.isDisabled = isDisabled
        self.allowDecimal = allowDecimal
    }
    #endif

    public var body: some View {
        VStack(spacing: 12) {
            amountAndNoteInputView
            /*
            if !showingAmountAndNote {
                amountAndNoteToggleButton
            } else {
                amountAndNoteInputView
            }
             */
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "button_done", bundle: .module)) {
                    focusedField = nil
                }
            }
        }
    }
    
    @ViewBuilder
    private var amountAndNoteToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingAmountAndNote = true
            }
        } label: {
            HStack(spacing: 6) {
                Text("receive_add_amount_note", bundle: .module)
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var amountAndNoteInputView: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                amountInputField
                Divider()
                    .padding(.leading, 25)
                    .padding(.trailing, 25)
                noteInputField
            }
        }
    }
    
    @ViewBuilder
    private var amountInputField: some View {
        HStack(spacing: 8) {
            TextField(amountPlaceholder, text: $amount)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.leading, 25)
                .padding(.vertical, 12)
                .focused($focusedField, equals: .amount)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.6 : 1.0)
                .accessibilityLabel(amountAccessibilityLabel)
                #if os(iOS)
                .keyboardType(keyboardType)
                #endif
                .onChange(of: amount) { oldValue, newValue in
                    if allowDecimal {
                        let filtered = newValue.filter { "0123456789.".contains($0) }
                        
                        // Ensure only one decimal point
                        let components = filtered.components(separatedBy: ".")
                        if components.count > 2 {
                            amount = oldValue
                        } else if filtered != newValue {
                            amount = filtered
                        }
                    } else {
                        // Only allow integers
                        let filtered = newValue.filter { "0123456789".contains($0) }
                        if filtered != newValue {
                            amount = filtered
                        }
                    }
                }
            
            if let unit = unitLabel {
                Text(unit)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                    .padding(.trailing, 25)
                    .accessibilityHidden(true)
            } else {
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var noteInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(notePlaceholder, text: $note)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, 25)
                .padding(.vertical, 12)
                .focused($focusedField, equals: .note)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.6 : 1.0)
                .accessibilityLabel(Text("accessibility_note_label", bundle: .module))
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
