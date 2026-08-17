//
//  DetailRow.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/5/25.
//

import SwiftUI

public struct DetailRow: View {
    let title: String
    let value: String
    let isCopyable: Bool
    let onCopy: ((String) -> Void)?

    public init(title: String, value: String, isCopyable: Bool = false, onCopy: ((String) -> Void)? = nil) {
        self.title = title
        self.value = value
        self.isCopyable = isCopyable
        self.onCopy = onCopy
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Read the title and full (untruncated) value as a single VoiceOver element.
            .accessibilityElement(children: .combine)

            if isCopyable {
                CopyButton(value, style: .plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Private Methods

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif

        // Announce the copy to VoiceOver so success isn't a silent action.
        AccessibilityNotification.Announcement(
            L10n.statusCopiedExclaim
        ).post()

        // Call the optional callback if provided (for showing copy success feedback)
        onCopy?(text)
    }
}

#Preview {
    VStack(spacing: 16) {
        DetailRow(
            title: "Address",
            value: "0x1234567890abcdef1234567890abcdef12345678",
            isCopyable: true
        )
        
        DetailRow(
            title: "Balance",
            value: "1.5 ETH"
        )
        
        DetailRow(
            title: "Transaction Hash",
            value: "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
            isCopyable: true
        )
        
        DetailRow(
            title: "Status",
            value: "Confirmed"
        )
    }
    .padding()
    .frame(width: 400)
}
