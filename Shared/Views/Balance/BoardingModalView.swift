//
//  BoardingModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import ArkeUI

private enum BoardingModalState: Hashable {
    case form
    case boarding
    case success
    case error(String)
}

struct BoardingModalView: View {
    let manager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var state: BoardingModalState = .form
    
    var body: some View {
        ZStack {
            switch state {
            case .form:
                BoardingModalFormView(
                    minimumAmount: manager.arkInfo?.minBoardAmount,
                    onConfirm: { amount in
                        Task {
                            await performBoarding(amount: amount)
                        }
                    },
                    onCancel: {
                        dismiss()
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .boarding:
                BoardingModalBoardingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            case .success:
                BoardingModalSuccessView {
                    dismiss()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .error(let errorMessage):
                LargeErrorView(
                    title: "error_boarding_failed",
                    errorMessage: errorMessage,
                    image: nil,
                    systemImage: "xmark.circle.fill",
                    systemImageColor: .Arke.blue,
                    onRetry: {
                        state = .form
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @MainActor
    private func performBoarding(amount: Int) async {
        state = .boarding
        
        do {
            try await manager.board(amount: amount)
            state = .success
        } catch {
            state = .error("Failed to board sats: \(error.localizedDescription)")
        }
    }
}
