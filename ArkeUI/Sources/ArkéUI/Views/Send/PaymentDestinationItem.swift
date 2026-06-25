//
//  PaymentDestinationItem.swift
//  Arké
//
//  Created by Christoph on 11/18/25.
//

import SwiftUI

public struct PaymentDestinationItem: View {
    let formatName: String
    let shortAddress: String
    let estimatedFee: Int?
    let isSelectable: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let contactName: String?
    let contactAvatar: Data?
    let viable: Bool
    let viabilityReason: String
    let showMatchedContact: Bool
    
    public init(
        formatName: String,
        shortAddress: String,
        estimatedFee: Int?,
        isSelectable: Bool,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        contactName: String? = nil,
        contactAvatar: Data? = nil,
        viable: Bool = true,
        viabilityReason: String? = nil,
        showMatchedContact: Bool = true
    ) {
        self.formatName = formatName
        self.shortAddress = shortAddress
        self.estimatedFee = estimatedFee
        self.isSelectable = isSelectable
        self.isSelected = isSelected
        self.onTap = onTap
        self.contactName = contactName
        self.contactAvatar = contactAvatar
        self.viable = viable
        self.viabilityReason = viabilityReason ?? String(localized: "status_available", bundle: .module)
        self.showMatchedContact = showMatchedContact
    }
    
    public var body: some View {
        Group {
            if isSelectable && viable {
                Button {
                    onTap()
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .help(viabilityReason)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("accessibility_hint_select_destination", bundle: .module))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            } else {
                rowContent
                    .help(viable ? viabilityReason : String(localized: "Cannot use: \(viabilityReason)", bundle: .module))
                    .accessibilityElement(children: .combine)
            }
        }
    }
    
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showMatchedContact, let contactName = contactName {
                HStack {
                    // Contact avatar
                    ContactAvatarView(avatarData: contactAvatar, size: 40, fallbackText: contactName)
                        //.opacity(viable ? 1.0 : 0.5)
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "label_known_address", bundle: .module))
                            .font(.body)
                            .foregroundColor(.arkeSecondary)
                        Text(contactName)
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    //.opacity(viable ? 1.0 : 0.5)
                }
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(formatName)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(shortAddress)
                        .font(.body)
                        .foregroundColor(isSelectable && viable ? .primary : .secondary)
                    
                    // Show viability reason for non-viable destinations
                    if !viable {
                        HStack(spacing: 5) {
                            /*
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.body)
                                .foregroundColor(.orange)
                            */
                            
                            Text(viabilityReason)
                                .font(.body)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                        }
                    }
                }
                
                Spacer()
                
                if let fee = estimatedFee {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "label_fee", bundle: .module))
                            .foregroundColor(.secondary)
                        
                        Text(fee > 0 ? "~\(BitcoinFormatter.shared.formatAmount(fee))" : String(localized: "label_free", bundle: .module))
                            .font(.body)
                            .foregroundColor(isSelectable && viable ? .primary : .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background {
            if isSelectable && isSelected && viable {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.Arke.gold.opacity(0.05))
            } else if !viable {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.05))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
    
    private var borderColor: Color {
        if !viable {
            return Color.arkeSeparatorColor.opacity(0.5)
        } else if isSelectable && isSelected {
            return .Arke.gold
        } else if isSelectable {
            return Color.arkeSeparatorColor
        } else {
            return Color.arkeSeparatorColor.opacity(0.5)
        }
    }
}

#Preview("Fee & Selected") {
    @Previewable @State var isSelected = true
    
    PaymentDestinationItem(
        formatName: "Bitcoin Address",
        shortAddress: "bc1q...xyz",
        estimatedFee: 250,
        isSelectable: true,
        isSelected: isSelected,
        onTap: { isSelected.toggle() }
    )
    .padding()
}

#Preview("No Fee") {
    @Previewable @State var isSelected = false
    
    PaymentDestinationItem(
        formatName: "Lightning Invoice",
        shortAddress: "lnbc...abc",
        estimatedFee: 0,
        isSelectable: true,
        isSelected: isSelected,
        onTap: { isSelected.toggle() }
    )
    .padding()
}

#Preview("Without Fee Info") {
    @Previewable @State var isSelected = false
    
    PaymentDestinationItem(
        formatName: "Payment Address",
        shortAddress: "tb1q...def",
        estimatedFee: nil,
        isSelectable: true,
        isSelected: isSelected,
        onTap: { isSelected.toggle() }
    )
    .padding()
}

#Preview("Not Selectable") {
    @Previewable @State var isSelected = false
    
    PaymentDestinationItem(
        formatName: "Payment Address",
        shortAddress: "tb1q...def",
        estimatedFee: 250,
        isSelectable: false,
        isSelected: isSelected,
        onTap: { isSelected.toggle() }
    )
    .padding()
}

#Preview("With Contact") {
    @Previewable @State var isSelected = false
    
    PaymentDestinationItem(
        formatName: "Lightning Address",
        shortAddress: "alice@example.com",
        estimatedFee: 0,
        isSelectable: true,
        isSelected: isSelected,
        onTap: { isSelected.toggle() },
        contactName: "Alice Smith",
        contactAvatar: nil,  // ContactAvatarView will show its built-in placeholder
        showMatchedContact: true
    )
    .padding()
}

#Preview("Not Viable - Insufficient Balance") {
    @Previewable @State var isSelected = false
    
    PaymentDestinationItem(
        formatName: "Bitcoin Address",
        shortAddress: "bc1q...xyz",
        estimatedFee: 250,
        isSelectable: true,
        isSelected: isSelected,
        onTap: { isSelected.toggle() },
        viable: false,
        viabilityReason: "Need 300 ₿ more"
    )
    .padding()
}

#Preview("Not Viable - Server Disconnected") {
    @Previewable @State var isSelected = false
    
    PaymentDestinationItem(
        formatName: "Lightning Invoice",
        shortAddress: "lnbc...abc",
        estimatedFee: 100,
        isSelectable: true,
        isSelected: isSelected,
        onTap: { isSelected.toggle() },
        viable: false,
        viabilityReason: "No connection"
    )
    .padding()
}
