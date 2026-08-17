//
//  ContactRow_iOS.swift
//  Arké
//
//  Created by Christoph on 12/4/25.
//

import SwiftUI
import ArkeUI

/// iOS-specific row component for displaying contact information
struct ContactRow_iOS: View {
    let contact: ContactModel
    let showStatistics: Bool
    let sendButtonStyle: SendButtonStyle
    let onTransactionCountTap: (() -> Void)?
    let onSendTap: (() -> Void)?
    
    enum SendButtonStyle {
        case icon           // Just an icon
        case capsule        // "Send" text in capsule
        case hidden         // No send button
    }
    
    // Convenience initializer for backward compatibility
    init(
        contact: ContactModel,
        showStatistics: Bool = true,
        sendButtonStyle: SendButtonStyle = .capsule,
        onTransactionCountTap: (() -> Void)? = nil,
        onSendTap: (() -> Void)? = nil
    ) {
        self.contact = contact
        self.showStatistics = showStatistics
        self.sendButtonStyle = sendButtonStyle
        self.onTransactionCountTap = onTransactionCountTap
        self.onSendTap = onSendTap
    }
    
    var body: some View {
        HStack(spacing: 15) {
            // Avatar
            avatarView
            
            // Contact info
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(showStatistics ? .body : .title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                // Address types or notes
                // addressInfoView
                
                // Transaction statistics
                if showStatistics {
                    statisticsView
                }
            }
            
            Spacer()
            
            // Send button
            sendButtonView
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var avatarView: some View {
        ContactAvatarView(
            avatarData: contact.avatarData,
            size: 44,
            fallbackText: contact.cachedName
        )
    }
    
    @ViewBuilder
    private var addressInfoView: some View {
        HStack(spacing: 8) {
            if contact.hasAddresses {
                Text(contact.addressTypesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let notes = contact.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(String(localized: "contacts_no_addresses", defaultValue: "No addresses"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    @ViewBuilder
    private var statisticsView: some View {
        if let transactionCount = contact.transactionCount, transactionCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if let onTransactionCountTap {
                    Button {
                        onTransactionCountTap()
                    } label: {
                        Text("\(transactionCount) transactions")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("\(transactionCount) transactions")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    if let sentAmount = contact.formattedSentAmount {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                            Text(sentAmount)
                        }
                        .font(.callout)
                        .foregroundColor(.primary)
                    }
                    
                    if let receivedAmount = contact.formattedReceivedAmount {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                            Text(receivedAmount)
                        }
                        .font(.callout)
                        .foregroundColor(.Arke.green)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var sendButtonView: some View {
        switch sendButtonStyle {
        case .icon:
            if contact.hasAddresses && contact.primaryAddress != nil {
                Button(action: { onSendTap?() }) {
                    Image(systemName: "paperplane.fill")
                }
                .accessibilityLabel(L10n.actionSendAddress)
                .buttonStyle(.borderedProminent)
            }
            
        case .capsule:
            Button {
                onSendTap?()
            } label: {
                Text(L10n.buttonSend)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        contact.hasAddresses ? Color.Arke.blue : .gray.opacity(0.3),
                        in: Capsule()
                    )
                    .foregroundStyle(contact.hasAddresses ? .white : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!contact.hasAddresses)
            
        case .hidden:
            EmptyView()
        }
    }
}
