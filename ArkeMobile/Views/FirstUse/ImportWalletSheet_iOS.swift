//
//  ImportWalletSheet_iOS.swift
//  Arké
//
//  The two import steps (phrase grid, then backup file) presented as a sheet
//  outside onboarding: a read-only device whose seed has not synced enters
//  the phrase here. The onboarding flow drives the same two views itself
//  because it owns the slide transitions between all its states.
//

import SwiftUI
import ArkeUI

struct ImportWalletSheet_iOS: View {
    let networkConfig: NetworkConfig
    let onCancel: () -> Void
    let onWalletImported: () -> Void

    private enum Step {
        case phrase
        case backupFile
    }

    @State private var step: Step = .phrase
    @State private var phrase: [String] = []

    var body: some View {
        ZStack {
            switch step {
            case .phrase:
                ImportPhraseView_iOS(
                    networkConfig: networkConfig,
                    initialWords: phrase,
                    onBack: onCancel,
                    onContinue: { words in
                        phrase = words
                        withAnimation(.smooth(duration: 0.4)) {
                            step = .backupFile
                        }
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))

            case .backupFile:
                ImportBackupFileView_iOS(
                    networkConfig: networkConfig,
                    phrase: phrase.joined(separator: " "),
                    onBack: {
                        withAnimation(.smooth(duration: 0.4)) {
                            step = .phrase
                        }
                    },
                    onWalletImported: onWalletImported
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.Arke.gold4)
        .clipped()
        .ignoresSafeArea()
    }
}
