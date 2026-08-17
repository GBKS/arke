//
//  AddressHallmark.swift
//
//  Arke's wrapper around the Hallmarks identicon library
//  (https://github.com/GBKS/hallmarks). Adapts the standalone Hallmark view
//  to the app: render mode follows the system color scheme, and the
//  accessibility label comes from the ArkeUI localization catalog.
//

import SwiftUI
import Hallmarks

/// A deterministic identicon for a Bitcoin or Ark address, for at-a-glance
/// visual address verification.
///
/// Usage:
///   AddressHallmark(address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
///       .frame(width: 64)
///
/// The view maintains its aspect ratio (taller than wide). Provide width via
/// `.frame(width:)` and let height size itself.
public struct AddressHallmark: View {
    @Environment(\.colorScheme) private var colorScheme

    let address: String
    let style: HallmarkStyle
    let bordered: Bool

    public init(address: String, style: HallmarkStyle = .standard, bordered: Bool = false) {
        self.address = address
        self.style = style
        self.bordered = bordered
    }

    public var body: some View {
        Hallmark(
            input: address,
            style: style,
            mode: colorScheme == .dark ? .dark : .light,
            bordered: bordered
        )
        .accessibilityLabel(Text(String(localized: "accessibility_address_identicon", defaultValue: "Address identicon", bundle: .module)))
    }
}

// MARK: - Preview

#Preview("Address hallmarks") {
    let addresses = [
        "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
        "bc1q5shngj24323nsrmxv99st02na6srekfctt30ch",
        "bc1prp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
        "tark1pemq45fepe2dcc3vp43xq8c4yywvn8m5kvkx0evf3jc8efg2hxsqkuw3xv",
    ]

    return VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 24) {
            ForEach(addresses, id: \.self) { addr in
                AddressHallmark(address: addr)
                    .frame(width: 45)
            }
        }

        HStack(spacing: 24) {
            ForEach(addresses, id: \.self) { addr in
                AddressHallmark(address: addr, style: .monochrome, bordered: true)
                    .frame(width: 45)
            }
        }
    }
    .padding()
}
