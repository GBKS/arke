//
//  AddressPatternsSettingView.swift
//  Ark wallet prototype
//
//  Settings sub-page explaining address patterns (Hallmarks), with the
//  toggle that shows or hides them across the app.
//

import SwiftUI
import ArkeUI

struct AddressPatternsSettingView: View {
    @AppStorage(UserDefaults.showAddressIconsKey)
    private var showAddressIcons: Bool = true

    // Fixed sample addresses so the header renders the same patterns every time.
    private static let sampleAddresses = [
        "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
        "bc1q5shngj24323nsrmxv99st02na6srekfctt30ch",
        "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        "bc1prp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
        "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
        "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy",
        "tark1pemq45fepe2dcc3vp43xq8c4yywvn8m5kvkx0evf3jc8efg2hxsqkuw3xv",
        "tark1wp3suf7e5q8c4yywvn8m5kvkx0evf3jc8efg2hxsqkuw3xvm9k4z7p",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                headerView

                VStack(alignment: .leading, spacing: 20) {
                    Text("settings_address_patterns")
                        .font(.system(.title, design: .serif))

                    Toggle(isOn: $showAddressIcons) {
                        Text(String(localized: "settings_address_patterns_toggle", defaultValue: "Show address patterns"))
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    }

                    Text(String(localized: "settings_address_patterns_explainer", defaultValue: "Every address gets its own unique pattern, generated from the address itself. A glance is enough to tell whether two addresses match, without comparing them character by character."))
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundColor(.secondary)

                    Text(String(localized: "settings_address_patterns_experimental", defaultValue: "This is an experimental feature. Patterns are most useful when you can compare them across apps — and for now, Arké is the first wallet to show them. Think of it as a preview of what address checking could feel like."))
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundColor(.secondary)

                    if let hallmarksURL = URL(string: "https://hallmarks.info") {
                        Link(destination: hallmarksURL) {
                            Text(String(localized: "settings_address_patterns_learn_more", defaultValue: "Learn more at hallmarks.info"))
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .padding()
            #if os(macOS)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            #endif
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // Live preview of actual address patterns in place of a static illustration.
    private var headerView: some View {
        VStack(spacing: 20) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(Self.sampleAddresses[(row * 4)..<(row * 4 + 4)], id: \.self) { address in
                        AddressHallmark(address: address, bordered: true)
                            .frame(width: 48)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background {
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.Arke.teal.opacity(0.08))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    AddressPatternsSettingView()
}
