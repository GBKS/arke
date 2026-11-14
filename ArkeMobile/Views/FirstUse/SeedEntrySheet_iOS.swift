//
//  SeedEntrySheet_iOS.swift
//  Arké
//
//  Seed-only recovery phrase entry for a device that is linked to the
//  account's wallet but whose key has not arrived through iCloud Keychain
//  (Device_Linking.md §4.2). The phrase is checked against the account's
//  wallet hash and saved to the keychain, and the device's registry row is
//  marked as holding the seed. It is never run through bark's import: that
//  would create a local wallet database and claim primary, which is the
//  surprise primary claim the link flow exists to remove.
//

import SwiftUI
import ArkeUI

struct SeedEntrySheet_iOS: View {
    let networkConfig: NetworkConfig
    let onCancel: () -> Void
    let onSeedSaved: () -> Void

    @Environment(\.securityService) private var securityService
    @Environment(\.serviceContainer) private var serviceContainer

    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        ImportPhraseView_iOS(
            networkConfig: networkConfig,
            initialWords: [],
            onBack: onCancel,
            onContinue: { words in
                Task { await save(words.joined(separator: " ")) }
            }
        )
        .background(Color.Arke.gold4)
        .ignoresSafeArea()
        .alert(String(localized: "seed_entry_error_title", defaultValue: "Recovery phrase not saved"),
               isPresented: $showingError) {
            Button(L10n.buttonOk) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save(_ phrase: String) async {
        switch await securityService.validateMnemonic(phrase) {
        case .valid:
            break
        case .invalid:
            fail(String(localized: "seed_entry_error_other_wallet",
                        defaultValue: "This recovery phrase belongs to a different wallet than the one on this iCloud account."))
            return
        case .validNoReference:
            // The account's hash has not reached this device, so the phrase
            // cannot be checked against it. Saving an unchecked seed could
            // pair this device with the wrong wallet.
            fail(String(localized: "seed_entry_error_no_reference",
                        defaultValue: "iCloud hasn't delivered the wallet's details yet. Try again in a moment."))
            return
        case .invalidFormat:
            fail(String(localized: "seed_entry_error_format",
                        defaultValue: "This is not a valid recovery phrase."))
            return
        }

        do {
            try await securityService.handleSeedImport(phrase)
            try? await serviceContainer.deviceRegistrationService.updateCurrentDeviceHasSeed(true)
            onSeedSaved()
        } catch {
            fail(String(format: String(localized: "seed_entry_error_save %@",
                                       defaultValue: "The recovery phrase could not be saved: %@"),
                        error.localizedDescription))
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
