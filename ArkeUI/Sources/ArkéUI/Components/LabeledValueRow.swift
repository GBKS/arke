//
//  LabeledValueRow.swift
//  ArkéUI
//
//  Created by Christoph on 7/8/26.
//
//  A single label/value row for data-heavy sections (X-Ray, diagnostics):
//  label left-aligned in secondary color, value right-aligned in monospaced.
//

import SwiftUI

public struct LabeledValueRow: View {
    private let label: String
    private let value: String
    private let valueColor: Color?

    /// - Parameters:
    ///   - label: Localized label shown on the left
    ///   - value: Value shown right-aligned in monospaced type
    ///   - valueColor: Optional color for the value (e.g. `.orange` for warnings)
    public init(_ label: String, value: String, valueColor: Color? = nil) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(valueColor ?? .primary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        LabeledValueRow("Fast", value: "2 sat/vB")
        LabeledValueRow("Estimated Blocks Behind", value: "12", valueColor: .orange)
        LabeledValueRow("Server", value: "https://ark.signet.2nd.dev")
    }
    .padding()
}
