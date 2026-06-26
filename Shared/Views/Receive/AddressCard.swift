//
//  AddressCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import ArkeUI

struct AddressCard: View {
    let address: String
    let shareContent: String?
    let label: String?
    let onTap: () -> Void
    
    @AppStorage(UserDefaults.showAddressIconsKey) private var showAddressIcons = true
    
    init(address: String, shareContent: String? = nil, label: String? = nil, onTap: @escaping () -> Void) {
        self.address = address
        self.shareContent = shareContent
        self.label = label
        self.onTap = onTap
    }
    
    private var fontSize: CGFloat {
        #if os(macOS)
        14
        #else
        17
        #endif
    }
    
    private func collapsedAddress() -> some View {
        let chunks = address.chunked(into: 4)
        let spacing = fontSize * 0.3
        
        return HStack(spacing: spacing) {
            ForEach(0..<min(2, chunks.count), id: \.self) { index in
                Text(chunks[index])
                    .foregroundStyle(.primary)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .fixedSize()
            }
            
            if chunks.count > 4 {
                Text(String(localized: "symbol_ellipsis"))
                    .foregroundStyle(.primary)
                    .fontWeight(.regular)
            }
            
            ForEach(max(2, chunks.count - 2)..<chunks.count, id: \.self) { index in
                Text(chunks[index])
                    .foregroundStyle(.primary)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let label {
                    HStack {
                        Text(label)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                
                collapsedAddress()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            Spacer()

            CopyButton(address, help: "action_copy_address")
        }
    }
}
