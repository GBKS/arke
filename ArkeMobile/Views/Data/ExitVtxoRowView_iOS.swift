//
//  ExitVtxoRowView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//


/**

A VTXO in the exit process

public struct ExitVtxo: Equatable, Hashable {
    /**
     * VTXO ID
     */
    public var vtxoId: String
    /**
     * Amount in sats
     */
    public var amountSats: UInt64
    /**
     * Current exit state
     */
    public var state: String
    /**
     * Whether this exit is claimable
     */
    public var isClaimable: Bool

    // Default memberwise initializers are never public by default, so we
    // declare one manually.
    public init(
        /**
         * VTXO ID
         */vtxoId: String,
        /**
         * Amount in sats
         */amountSats: UInt64,
        /**
         * Current exit state
         */state: String,
        /**
         * Whether this exit is claimable
         */isClaimable: Bool) {
        self.vtxoId = vtxoId
        self.amountSats = amountSats
        self.state = state
        self.isClaimable = isClaimable
    }
}
*/

import SwiftUI
import Bark

struct ExitVtxoRowView_iOS: View {
    let exit: ExitVtxo
    let isSelected: Bool
    let latestBlockHeight: Int?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortVtxoId)
                        .font(.system(.body, design: .monospaced))
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(formattedAmount)
                    .font(.system(.body, design: .monospaced))

                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    // MARK: - Computed Properties
    
    private var shortVtxoId: String {
        exit.shortVtxoId
    }
    
    private var formattedAmount: String {
        exit.formattedAmount
    }
    
    private var statusText: String {
        exit.stateDisplayName
    }
}
