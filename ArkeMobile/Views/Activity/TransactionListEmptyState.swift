//
//  TransactionListEmptyState.swift
//  Ark wallet prototype
//
//  Created by Christoph on 12/05/25.
//

import SwiftUI
import ArkeUI

/// Shared empty state component for transaction lists
struct TransactionListEmptyState: View {
    let filterContext: FilterContext
    let onShowFaucet: (() -> Void)?
    let onNavigateToReceive: (() -> Void)?
    
    enum FilterContext: Equatable {
        case none
        case tag(name: String)
        case contact(name: String)
        /// Secondary device whose first CloudKit import hasn't landed yet. An
        /// empty list is the truth for every other case; here it is just "we
        /// don't know yet", and presenting it as an empty wallet reads as a
        /// broken one (over a minute observed on a fresh install).
        case syncingFromCloud

        var title: String {
            switch self {
            case .none:
                return String(localized: "transaction_list_empty_title", defaultValue: "Ready when you are")
            case .tag(let name):
                return String(localized: "transaction_list_empty_tag_title %@", defaultValue: "No Transactions in \"\(name)\"")
            case .contact(let name):
                return String(localized: "transaction_list_empty_contact_title %@", defaultValue: "No Transactions with \(name)")
            case .syncingFromCloud:
                return String(localized: "transaction_list_syncing_title", defaultValue: "Syncing from iCloud")
            }
        }

        func message(isTestnet: Bool) -> String? {
            switch self {
            case .none:
                return isTestnet ? String(localized: "transaction_list_empty_message_testnet", defaultValue: "Get started by funding your wallet with test bitcoin") : nil
            case .tag:
                return String(localized: "transaction_list_empty_tag_message", defaultValue: "Transactions you tag will appear here")
            case .contact:
                return String(localized: "transaction_list_empty_contact_message", defaultValue: "Transactions with this contact will appear here")
            case .syncingFromCloud:
                return String(localized: "transaction_list_syncing_message", defaultValue: "Your balance and activity are on their way from your other device. This can take a few minutes the first time.")
            }
        }

        var icon: String? {
            switch self {
            case .none:
                return nil
            case .tag:
                return "tag"
            case .contact:
                return "person"
            case .syncingFromCloud:
                return "arrow.trianglehead.2.clockwise.rotate.90.icloud"
            }
        }
    }

    init(filterTag: PersistentTag? = nil, filterContact: PersistentContact? = nil, onShowFaucet: (() -> Void)? = nil, onNavigateToReceive: (() -> Void)? = nil, isSyncingFromCloud: Bool = false) {
        if isSyncingFromCloud {
            // Takes precedence over the filter contexts: with nothing synced,
            // "no transactions in this tag" isn't a claim we can make either
            self.filterContext = .syncingFromCloud
        } else if let tag = filterTag {
            self.filterContext = .tag(name: tag.name)
        } else if let contact = filterContact {
            self.filterContext = .contact(name: contact.cachedName)
        } else {
            self.filterContext = .none
        }
        self.onShowFaucet = onShowFaucet
        self.onNavigateToReceive = onNavigateToReceive
    }
    
    var body: some View {
        ContentUnavailableView {
            if let icon = filterContext.icon {
                Label(filterContext.title, systemImage: icon)
            } else {
                Text(filterContext.title)
            }
        } description: {
            if let message = filterContext.message(isTestnet: onShowFaucet != nil) {
                Text(message)
            }
        } actions: {
            if filterContext == .none, let onShowFaucet = onShowFaucet {
                Button {
                    onShowFaucet()
                } label: {
                    HStack {
                        Image(systemName: "book.pages.fill")
                            .foregroundStyle(Color.Arke.gold)
                        Text(String(localized: "transaction_list_empty_guide_button", defaultValue: "See the test guide"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .tint(Color.Arke.gold)
            } else if filterContext == .none, onShowFaucet == nil, let onNavigateToReceive = onNavigateToReceive {
                Button {
                    onNavigateToReceive()
                } label: {
                    Text(String(localized: "activity_receive_bitcoin", defaultValue: "Receive Bitcoin"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(Color.Arke.gold)
                .padding(.top, 10)
            }
        }
    }
}
