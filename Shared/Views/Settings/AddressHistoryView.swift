//
//  AddressHistoryView.swift
//  Arké
//
//  Created by Christoph on 01/12/26.
//

import SwiftUI
import SwiftData
import ArkeUI

struct AddressHistoryView: View {
    @Query(
        filter: #Predicate<PersistentAddress> { $0.isActive },
        sort: \PersistentAddress.generatedAt,
        order: .reverse
    )
    private var allAddresses: [PersistentAddress]

    @Environment(WalletManager.self) private var walletManager

    @State private var copiedAddress: String?
    @State private var isGeneratingArk = false
    @State private var isGeneratingBitcoin = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Computed properties to filter by type
    private var arkAddresses: [PersistentAddress] {
        allAddresses.filter { $0.addressType == "ark" }
    }

    private var bitcoinAddresses: [PersistentAddress] {
        allAddresses.filter { $0.addressType == "onchain" }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                // Ark Addresses Section
                if !arkAddresses.isEmpty {
                    Section {
                        ForEach(arkAddresses) { address in
                            AddressHistoryRowView(
                                address: address,
                                copiedAddress: $copiedAddress
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: {
                        sectionHeader(
                            title: "Payments Addresses (Ark)",
                            description: "Re-usable for many payments.",
                            isGenerating: isGeneratingArk,
                            onAdd: { generateAddress(type: .ark) }
                        )
                    }
                    .padding(.vertical, 8)
                }

                // Bitcoin Addresses Section
                if !bitcoinAddresses.isEmpty {
                    Section {
                        ForEach(bitcoinAddresses) { address in
                            AddressHistoryRowView(
                                address: address,
                                copiedAddress: $copiedAddress
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: {
                        sectionHeader(
                            title: "Savings Addresses (Bitcoin)",
                            description: "Use once to preserve your privacy.",
                            isGenerating: isGeneratingBitcoin,
                            onAdd: { generateAddress(type: .onchain) }
                        )
                    }
                    .padding(.vertical, 8)
                }

                // Empty State
                if allAddresses.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(String(localized: "receive_no_addresses", defaultValue: "No addresses yet"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(String(localized: "receive_addresses_empty", defaultValue: "Addresses will appear here as they are generated"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
            }
        }
        .navigationTitle(L10n.receiveAddressHistory)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .alert(L10n.errorTitle, isPresented: $showError) {
            Button(L10n.buttonOk) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(title: String, description: String, isGenerating: Bool, onAdd: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button {
                onAdd()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Arke.gold)
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                }
            }
            .buttonStyle(.bordered)
            .tint(.Arke.gold)
            .disabled(isGenerating)
        }
    }

    // MARK: - Address Generation

    private func generateAddress(type: AddressType) {
        Task {
            // Set loading state
            if type == .ark {
                isGeneratingArk = true
            } else {
                isGeneratingBitcoin = true
            }

            do {
                let newAddress = try await walletManager.generateNewAddress(
                    type: type,
                    strategy: .userRequested
                )

                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif

                print("✅ Successfully generated \(type.displayName): \(newAddress.address)")
            } catch let error as AddressError {
                handleAddressError(error, type: type)
            } catch {
                errorMessage = "Failed to generate address: \(error.localizedDescription)"
                showError = true
            }

            // Clear loading state
            if type == .ark {
                isGeneratingArk = false
            } else {
                isGeneratingBitcoin = false
            }
        }
    }

    private func handleAddressError(_ error: AddressError, type: AddressType) {
        switch error {
        case .gapLimitExceeded(let unusedCount):
            errorMessage = """
            Cannot generate new Bitcoin address. You have \(unusedCount) unused addresses.

            For privacy and wallet recovery, please use your existing unused addresses before generating new ones.
            """
            showError = true
        case .duplicateAddress:
            errorMessage = "This address already exists in your wallet."
            showError = true
        case .addressNotFound:
            errorMessage = "Address not found."
            showError = true
        case .invalidAddressType:
            errorMessage = "Invalid address type."
            showError = true
        }
    }
}

// MARK: - Address Row View

struct AddressHistoryRowView: View {
    let address: PersistentAddress
    @Binding var copiedAddress: String?
    @State private var isExpanded = false
    @State private var showingCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // Address string with expandable view
                ExpandableAddressView(address: address.address, isExpanded: $isExpanded, animated: false)

                // Additional info row
                HStack(spacing: 4) {
                    Text(address.generatedAt, style: .relative)
                        .font(.caption)
                    Text(String(localized: "label_ago", defaultValue: "ago"))
                        .font(.caption)

                    if let index = address.derivationIndex {
                        Text(L10n.symbolBullet)
                            .foregroundColor(.secondary)
                        Text(String(localized: "format_address_number", defaultValue: "Address #\(index)"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Dedicated copy button
            Button {
                copyAddress()
            } label: {
                Image(systemName: showingCopied ? "checkmark" : "doc.on.doc.fill")
                    .foregroundStyle(showingCopied ? Color.Arke.green : Color.Arke.gold)
                    .frame(width: 10, height: 10)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(showingCopied ? 1.1 : 1.0)
            }
            .buttonStyle(.bordered)
            .tint(showingCopied ? .Arke.green : .Arke.gold)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .sensoryFeedback(.success, trigger: showingCopied)
    }

    // MARK: - Actions

    private func copyAddress() {
        #if os(iOS)
        UIPasteboard.general.string = address.address
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address.address, forType: .string)
        #endif

        // Show copied feedback
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showingCopied = true
            copiedAddress = address.address
        }

        // Clear feedback after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation {
                showingCopied = false
                if copiedAddress == address.address {
                    copiedAddress = nil
                }
            }
        }
    }
}
