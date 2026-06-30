//
//  VTXOModel+Bark.swift
//  Ark wallet prototype
//
//  The `VTXOModel` value type lives in the ArkéUI package as a pure, previewable
//  model. This file maps Bark's `Vtxo` into it at the app boundary, keeping the
//  model free of Bark/FFI (which breaks previews).
//

import Foundation
import Bark
import ArkeUI

// Extension for conversion from SDK types
extension VTXOModel {
    /// Initialize from SDK's Vtxo type
    init(from vtxo: Vtxo) {
        // Map SDK state string to VTXOState enum
        let state: VTXOState = {
            switch vtxo.state.lowercased() {
            case "spendable": return .spendable
            case "spent": return .spent
            case "locked": return .locked
            case "pending": return .pending
            default: return .pending
            }
        }()

        // Map SDK kind string to VTXOKind enum
        let kind: VTXOKind = {
            switch vtxo.kind.lowercased() {
            case "board": return .board
            case "round": return .round
            case "arkoor": return .arkoor
            case "pubkey": return .pubkey
            case "checkpoint": return .checkpoint
            case "server-htlc-send", "serverhtlcsend": return .serverHTLCSend
            case "server-htlc-receive", "serverhtlcreceive": return .serverHTLCRecv
            case "expiry": return .expiry
            default: return .round
            }
        }()

        self.init(
            id: vtxo.id,
            amountSat: Int(vtxo.amountSats),
            expiryHeight: Int(vtxo.expiryHeight),
            kind: kind,
            state: state,
            exitDepth: vtxo.exitDepth,
            exitTxWeightWu: vtxo.exitTxWeightWu
        )
    }
}
