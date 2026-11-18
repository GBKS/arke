//
//  SendModalState.swift
//  Arké
//
//  Created by Christoph on 12/8/25.
//

enum SendModalState: Equatable {
    case sending
    case success
    case error(String)
    /// The payment may or may not have gone through (`LightningSendFailure.isUnconfirmed`)
    case unconfirmed(String)
}
