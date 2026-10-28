//
//  SheetDestinationDisplayView.swift
//  Arké
//
//  Created by Christoph on 11/19/25.
//

import SwiftUI
import ArkeUI

struct SheetDestinationDisplayView: View {
    let primaryDisplayDestination: DisplayDestination?
    let alternativeDisplayDestinations: [DisplayDestination]
    let primaryDestinationLabel: String
    let isSimpleAddress: Bool
    let showMatchedContact: Bool
    let formatNameOverride: String?

    /// The selected row: destination plus the balance it is paid from. A
    /// bitcoin address has one row per source, so the destination id alone
    /// would not tell them apart.
    @Binding var selectedChoice: PaymentDestinationSelector.Choice?
    @State private var isSheetPresented = false

    private var hasAlternativeDestinations: Bool {
        !alternativeDisplayDestinations.isEmpty
    }

    var body: some View {
        if let primaryDisplay = primaryDisplayDestination {
            VStack(spacing: 10) {
                /*
                // Header with label (skip for simple addresses)
                if !isSimpleAddress {
                    HStack {
                        Text(primaryDestinationLabel)
                            .font(.title2)

                        Spacer()
                    }
                }
                */

                // Primary/Selected destination display. A button only when
                // there is something to choose; a disabled button dims its
                // label, and the address was hard to read for the common
                // single-destination case (Christoph, device 2026-10-27)
                if hasAlternativeDestinations {
                    Button {
                        isSheetPresented = true
                    } label: {
                        primaryDestinationItem(primaryDisplay)
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.down")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 20)
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    primaryDestinationItem(primaryDisplay)
                }
            }
            .sheet(isPresented: $isSheetPresented) {
                DestinationSelectionSheet(
                    allDestinations: [primaryDisplay] + alternativeDisplayDestinations,
                    selectedChoice: $selectedChoice,
                    showMatchedContact: showMatchedContact,
                    onDismiss: {
                        isSheetPresented = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

extension SheetDestinationDisplayView {
    /// The primary destination as shown in the row, with or without a button around it
    fileprivate func primaryDestinationItem(_ primaryDisplay: DisplayDestination) -> some View {
        PaymentDestinationItem(
            formatName: formatNameOverride ?? primaryDisplay.payFromTitle,
            shortAddress: primaryDisplay.destination.shortAddress,
            estimatedFee: nil, // primaryDisplay.estimatedFee
            isSelectable: false,
            isSelected: false,
            onTap: {},
            contactName: primaryDisplay.matchedContact?.displayName,
            contactAvatar: primaryDisplay.matchedContact?.avatarData,
            viable: primaryDisplay.viable,
            viabilityReason: primaryDisplay.viabilityReason,
            showMatchedContact: showMatchedContact
        )
    }
}

// MARK: - "Pay from" Sheet

/// Which balance the payment leaves from. One row per balance and rail
/// the ranker offers; the recipient is not repeated here, the form above
/// shows it (`Features/Send_Onchain_From_Payments.md` §9, DECIDED
/// 2026-10-28).
private struct DestinationSelectionSheet: View {
    let allDestinations: [DisplayDestination]
    @Binding var selectedChoice: PaymentDestinationSelector.Choice?
    let showMatchedContact: Bool
    let onDismiss: () -> Void

    var body: some View {
        // Same shape as the speed sheet next door: a serif header in the
        // content, not a navigation-bar title (the app's modals set their
        // titles this way; Christoph, 2026-10-28)
        VStack(spacing: 20) {
            Text(String(localized: "nav_title_pay_from", defaultValue: "Pay from"))
                .font(.system(size: 24, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 30)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(allDestinations, id: \.choice) { displayDest in
                        FundingSourceRow(
                            balanceName: displayDest.title,
                            availableSats: displayDest.availableBalance,
                            railCaption: railCaption(for: displayDest),
                            addressCaption: addressCaption(for: displayDest),
                            estimatedFee: displayDest.estimatedFee,
                            isSelected: selectedChoice == displayDest.choice,
                            viable: displayDest.viable,
                            viabilityReason: displayDest.viabilityReason,
                            onTap: {
                                selectedChoice = displayDest.choice
                                onDismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: 450)
    }

    /// The rail, only when another row leaves from the same balance
    private func railCaption(for row: DisplayDestination) -> String? {
        let sharesBalance = allDestinations.contains {
            $0.choice != row.choice && $0.title == row.title
        }
        return sharesBalance ? row.railName : nil
    }

    /// The address, only when another row shares balance and rail
    private func addressCaption(for row: DisplayDestination) -> String? {
        let sharesRail = allDestinations.contains {
            $0.choice != row.choice && $0.title == row.title && $0.railName == row.railName
        }
        return sharesRail ? row.destination.shortAddress : nil
    }
}
