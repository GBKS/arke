//
//  TransactionIconView.swift
//  Arké
//
//  Created by Christoph on 7/28/26.
//

import SwiftUI
import ArkeUI

/// The transaction icon used across activity UI: contact avatar,
/// internal-transfer artwork, tag emoji tile, or a tinted type symbol — with
/// a small tag badge over the avatar when both a contact and a tag are
/// assigned. All metrics scale from `size`; the reference design is the 44pt
/// transaction list row.
struct TransactionIconView: View {
    let transaction: TransactionModel
    var size: CGFloat = 44
    /// Bumps the translucent tile tints so they stay readable on dark
    /// backdrops like the swipe card header.
    var onDark: Bool = false

    private var cornerRadius: CGFloat { size * 8 / 44 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            iconTile

            // Tag emoji badge over the contact avatar
            if let firstTag = transaction.associatedTags.first,
               transaction.associatedContacts.first != nil {
                Text(firstTag.emoji)
                    .font(.system(size: size * 9 / 44))
                    .frame(width: size * 16 / 44, height: size * 16 / 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .offset(x: size * 4 / 44, y: size * 4 / 44)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var iconTile: some View {
        if let contact = transaction.associatedContacts.first {
            ContactAvatarView(avatarData: contact.avatarData, size: size)
        } else if transaction.isInternalTransfer {
            Image(internalImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else if let firstTag = transaction.associatedTags.first {
            Text(firstTag.emoji)
                .font(.system(size: size * 11 / 44))
                .frame(width: size, height: size)
                .background(firstTag.color.opacity(onDark ? 0.35 : 0.2))
                .foregroundColor(firstTag.color)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            Image(systemName: iconName)
                .font(.system(size: size * 20 / 44))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(iconColor.opacity(onDark ? 0.25 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Category artwork for internal transfers ("wallet"/"safe" assets)
    private var internalImageName: String {
        if let category = transaction.category {
            // Special case: onchain_send with bark.offboard subsystem should use offboarding logic
            if category == .onchainSend, transaction.subsystemName == "bark.offboard" {
                return "safe"
            }

            switch category {
            case .boarding, .refresh:
                return "wallet"
            case .offboarding:
                return "safe"
            case .onchainTransaction:
                // Onchain self-transfers use safe image
                return transaction.subsystemKind == "self_transfer" ? "safe" : "wallet"
            default:
                return "wallet"
            }
        }

        // Check for exit subsystem
        if transaction.subsystemName == "bark.exit" {
            return "safe"
        }

        return "wallet"
    }

    /// Returns the appropriate icon name based on transaction category or type
    private var iconName: String {
        // For internal transfers, use category-specific icons
        if transaction.isInternalTransfer, let category = transaction.category {
            // Special case: onchain_send with bark.offboard subsystem should use offboarding icon
            if category == .onchainSend, transaction.subsystemName == "bark.offboard" {
                return MovementCategory.offboarding.icon
            }

            return category.icon
        }

        // For other transactions, use type-based icons
        return transaction.transactionType.iconName
    }

    /// Returns the appropriate icon color based on transaction status
    private var iconColor: Color {
        // Cancelled is terminal and wins over the exit-progress check below,
        // which would otherwise show a never-completing pending state.
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        // Special case for unilateral exits: only complete when claimed.
        // isExitComplete reads the persisted movement status first, so
        // completed exits render correctly at launch before the in-memory
        // exit caches are populated.
        if transaction.hasUnilateralExit {
            if transaction.isExitComplete {
                if transaction.isInternalTransfer {
                    return .gray
                }
                return transaction.transactionType.iconColor
            }
            // Exit is still in progress (not yet claimed)
            return .Arke.blue
        }

        switch transaction.transactionStatus {
        case .confirmed:
            // For confirmed transactions, use semantic colors
            if transaction.isInternalTransfer {
                return .gray
            }
            return transaction.transactionType.iconColor

        case .pending:
            return .Arke.blue

        case .failed:
            return .Arke.red

        case .cancelled:
            return .gray
        }
    }
}
