//
//  AddressReviewSheet.swift
//  ArkeUI
//
//  Created by Assistant on 6/19/26.
//

import SwiftUI

public struct AddressReviewSheet: View {
    let address: String
    let title: String
    let showAddressIcons: Bool
    @Environment(\.dismiss) private var dismiss

    public init(address: String, title: String? = nil, showAddressIcons: Bool = true) {
        self.address = address
        self.title = title ?? String(localized: "address_review_sheet_title", defaultValue: "Review Address", bundle: .module)
        self.showAddressIcons = showAddressIcons
    }

    public var body: some View {
        VStack(spacing: 25) {
            HStack(spacing: 12) {
                if showAddressIcons {
                    AddressPattern(address: address, bordered: true)
                        .frame(width: 40)
                }

                Text(title)
                    .font(.system(size: 24, design: .serif))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.top, 30)

            VerifiableAddressView(address: address)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview("Ark Address") {
    AddressReviewSheet(
        address: "ark1pu6h30w3zqqp835jkvwgyqpv6cgkv684d6tr2j4uk3nxlxfule8pzcjafkhg0zgezqypkx063ew44fgnw2n38c7m5qn5jcnt82c0f363jvkm88khg7lzhlvs7dqxva",
        title: "Payments address",
        showAddressIcons: true
    )
}

#Preview("Bitcoin address") {
    AddressReviewSheet(
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        title: "Savings address (fallback)",
        showAddressIcons: true
    )
}

#Preview("Without Address Icons") {
    AddressReviewSheet(
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        showAddressIcons: false
    )
}
