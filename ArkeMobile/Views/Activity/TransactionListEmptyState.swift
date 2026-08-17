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
        
        var title: String {
            switch self {
            case .none:
                return String(localized: "transaction_list_empty_title", defaultValue: "Ready when you are")
            case .tag(let name):
                return String(localized: "transaction_list_empty_tag_title %@", defaultValue: "No Transactions in \"\(name)\"")
            case .contact(let name):
                return String(localized: "transaction_list_empty_contact_title %@", defaultValue: "No Transactions with \(name)")
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
            }
        }
    }
    
    init(filterTag: PersistentTag? = nil, filterContact: PersistentContact? = nil, onShowFaucet: (() -> Void)? = nil, onNavigateToReceive: (() -> Void)? = nil) {
        if let tag = filterTag {
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
