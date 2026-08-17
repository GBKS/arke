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
    
    @Binding var selectedDestinationId: UUID?
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
                
                // Primary/Selected destination display
                Button {
                    if hasAlternativeDestinations {
                        isSheetPresented = true
                    }
                } label: {
                    PaymentDestinationItem(
                        formatName: formatNameOverride ?? primaryDisplay.destination.format.simplifiedDisplayName,
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
                    .overlay(alignment: .trailing) {
                        if hasAlternativeDestinations {
                            Image(systemName: "chevron.down")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 20)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasAlternativeDestinations)
            }
            .sheet(isPresented: $isSheetPresented) {
                DestinationSelectionSheet(
                    allDestinations: [primaryDisplay] + alternativeDisplayDestinations,
                    selectedDestinationId: $selectedDestinationId,
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

// MARK: - Destination Selection Sheet

private struct DestinationSelectionSheet: View {
    let allDestinations: [DisplayDestination]
    @Binding var selectedDestinationId: UUID?
    let showMatchedContact: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(allDestinations, id: \.destination.id) { displayDest in
                        Button {
                            selectedDestinationId = displayDest.destination.id
                            onDismiss()
                        } label: {
                            PaymentDestinationItem(
                                formatName: displayDest.destination.format.simplifiedDisplayName,
                                shortAddress: displayDest.destination.shortAddress,
                                estimatedFee: displayDest.estimatedFee,
                                isSelectable: true,
                                isSelected: selectedDestinationId == displayDest.destination.id,
                                onTap: {
                                    selectedDestinationId = displayDest.destination.id
                                    onDismiss()
                                },
                                contactName: displayDest.matchedContact?.displayName,
                                contactAvatar: displayDest.matchedContact?.avatarData,
                                viable: displayDest.viable,
                                viabilityReason: displayDest.viabilityReason,
                                showMatchedContact: showMatchedContact
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!displayDest.viable)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "nav_title_select_payment_method", defaultValue: "Select Payment Method"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                /*
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
                */
            }
        }
    }
}
