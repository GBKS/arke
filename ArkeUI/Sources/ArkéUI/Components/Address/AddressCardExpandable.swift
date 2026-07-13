//
//  AddressCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

public struct AddressCardExpandable: View {
    let address: String
    let shareContent: String?
    let label: String?
    @State private var showingCopied = false
    @State private var isExpanded = false
    
    public init(address: String, shareContent: String? = nil, label: String? = nil) {
        self.address = address
        self.shareContent = shareContent
        self.label = label
    }
    
    public var body: some View {
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
                
                ExpandableAddressView(address: address, isExpanded: $isExpanded)
            }
            
            Spacer()
            
            Button {
                copyToClipboard(address)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showingCopied = true
                }
                
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation {
                        showingCopied = false
                    }
                }
            } label: {
                Image(systemName: showingCopied ? "checkmark" : "doc.on.doc.fill")
                    .foregroundStyle(showingCopied ? Color.Arke.green : Color.Arke.gold)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
                    .padding (.vertical, 4)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(showingCopied ? 1.1 : 1.0)
            }
            .buttonStyle(.bordered)
            .tint(showingCopied ? .Arke.green : .Arke.gold)
            .help(Text("action_copy_address", bundle: .module))
        }
    }
}

#Preview {
    AddressCardExpandable(
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        shareContent: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        label: "Savings address"
    )
    .padding()
}
