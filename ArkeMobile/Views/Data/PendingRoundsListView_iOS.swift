//
//  PendingRoundsListView_iOS.swift
//  Arké
//
//  Display pending rounds and their locked VTXOs
//

import SwiftUI
import ArkeUI
import Bark

struct PendingRoundsListView_iOS: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @State private var rounds: [RoundState] = []
    @State private var lockedVtxos: [Vtxo] = []
    @State private var isLoadingRounds = false
    @State private var error: String?
    
    private var totalLockedAmount: UInt64 {
        lockedVtxos.reduce(into: 0) { $0 += $1.amountSats }
    }
    
    private var formattedTotalAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(totalLockedAmount))
    }
    
    private var ongoingRounds: [RoundState] {
        rounds.filter { $0.ongoing }
    }
    
    private var pausedRounds: [RoundState] {
        rounds.filter { !$0.ongoing }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("data_pending_rounds")
                        .font(.system(size: 24, design: .serif))
                    
                    if !rounds.isEmpty {
                        Text("\(rounds.count) round\(rounds.count == 1 ? "" : "s") • \(formattedTotalAmount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
                .padding(.horizontal)
            
            // Round List
            if isLoadingRounds {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
                .padding(.horizontal)
            } else if let error = error {
                ErrorBox(errorMessage: error)
                    .padding(.horizontal)
            } else if rounds.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("data_no_pending_rounds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    // Ongoing rounds section
                    if !ongoingRounds.isEmpty {
                        ForEach(Array(ongoingRounds.enumerated()), id: \.element.id) { index, round in
                            RoundRowView(
                                round: round,
                                lockedVtxos: lockedVtxos
                            )
                            
                            if index < ongoingRounds.count - 1 {
                                Divider()
                                    .padding(.horizontal, 12)
                            }
                        }
                        
                        // Divider between ongoing and paused if both exist
                        if !pausedRounds.isEmpty {
                            Divider()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // Paused rounds section
                    if !pausedRounds.isEmpty {
                        ForEach(Array(pausedRounds.enumerated()), id: \.element.id) { index, round in
                            RoundRowView(
                                round: round,
                                lockedVtxos: lockedVtxos
                            )
                            
                            if index < pausedRounds.count - 1 {
                                Divider()
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: reloadTrigger) {
            await loadRounds()
        }
    }
    
    private func loadRounds() async {
        isLoadingRounds = true
        error = nil
        
        print("loadPendingRounds")
        
        do {
            // Get pending rounds and locked VTXOs
            rounds = try await walletManager.pendingRoundStates()
            
            // Get all VTXOs and filter for locked ones
            let allVtxos = try await walletManager.allVtxos()
            lockedVtxos = allVtxos.filter { $0.state == "locked" }
            
            print("pending rounds: \(rounds.count)")
            print("locked VTXOs: \(lockedVtxos.count)")
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingRounds = false
    }
}

// MARK: - Round Row View

private struct RoundRowView: View {
    @Environment(WalletManager.self) private var walletManager
    let round: RoundState
    let lockedVtxos: [Vtxo]
    @State private var isCancelling = false
    @State private var showCancelConfirmation = false
    
    private var roundLockedSats: UInt64 {
        // For now, show total locked sats since we don't have round-to-VTXO mapping
        lockedVtxos.reduce(0) { $0 + $1.amountSats }     
    }
    
    private var formattedAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(roundLockedSats))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(round.ongoing ? Color.Arke.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: round.ongoing ? "arrow.triangle.2.circlepath" : "pause.circle")
                    .foregroundStyle(round.ongoing ? Color.Arke.green : .orange)
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Round \(round.id)")
                        .font(.system(size: 15, weight: .semibold))
                    
                    if round.ongoing {
                        Text("status_ongoing")
                            .font(.caption)
                            .foregroundStyle(Color.Arke.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.Arke.green.opacity(0.2))
                            .cornerRadius(4)
                    } else {
                        Text("status_finalizing")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                if !lockedVtxos.isEmpty {
                    Text("\(lockedVtxos.count) locked VTXO\(lockedVtxos.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            if roundLockedSats > 0 {
                Text(formattedAmount)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            /*
            // Cancel button (only for non-ongoing rounds)
            if !round.ongoing {
                if isCancelling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                    .contentShape(Circle())
                }
            }
            */
        }
        .padding(.vertical, 12)
        .alert("alert_cancel_round", isPresented: $showCancelConfirmation) {
            Button("data_cancel_round", role: .destructive) {
                Task {
                    await cancelRound()
                }
            }
            Button("data_keep_round", role: .cancel) { }
        } message: {
            Text("This will cancel round \(round.id) and release the locked VTXOs.")
        }
    }
    
    private func cancelRound() async {
        isCancelling = true
        defer { isCancelling = false }
        
        do {
            try await walletManager.cancelPendingRound(roundId: round.id)
            // Trigger a refresh of the parent view by refreshing wallet data
            await walletManager.refresh()
        } catch {
            print("Failed to cancel round \(round.id): \(error)")
        }
    }
}
