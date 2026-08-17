//
//  AddressNotFoundErrorCard.swift
//  Arké
//
//  Created by Christoph on 11/19/25.
//

import SwiftUI
import ArkeUI

/// Displays an error when the provided address doesn't match any contact addresses
struct AddressNotFoundErrorCard: View {
    let providedAddress: String
    let contactName: String
    let contactAddressCount: Int
    
    private var shortAddress: String {
        guard providedAddress.count > 16 else { return providedAddress }
        let start = providedAddress.prefix(8)
        let end = providedAddress.suffix(8)
        return "\(start)...\(end)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                
                Text(String(localized: "error_address_not_found", defaultValue: "Address Not Found"))
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "send_address_not_saved", defaultValue: "The address you're trying to pay to is not saved for **\(contactName)**."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(String(localized: "format_address_label", defaultValue: "Address: `\(shortAddress)`"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                
                Text(addressCountMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Arke.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.Arke.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var addressCountMessage: String {
        if contactAddressCount == 0 {
            return "This contact has no saved addresses. You may need to add this address to the contact first."
        } else if contactAddressCount == 1 {
            return "This contact has 1 saved address on file, but it doesn't match. You may need to add this address to the contact."
        } else {
            return "This contact has \(contactAddressCount) saved addresses on file, but none match. You may need to add this address to the contact."
        }
    }
}
