//
//  SendModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

enum SendModalState {
    case sending
    case success
    case error(String)
}

struct SendModalView: View {
    let state: SendModalState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        switch state {
        case .sending:
            SendModalSendingView()
        case .success:
            SendModalSuccessView {
                dismiss()
            }
        case .error(let errorMessage):
            SendModalErrorView(errorMessage: errorMessage) {
                dismiss()
            }
        }
    }
}

#Preview("Success") {
    SendModalView(state: .success)
}
