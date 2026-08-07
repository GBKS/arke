//
//  RoundStateDebugger.swift
//  Arké
//
//  Debug helper for logging round state information
//

import Foundation
import Bark

/// Helper for debugging and logging round state information
struct RoundStateDebugger {
    
    /// Logs detailed information about all pending rounds
    /// - Parameters:
    ///   - rounds: Array of RoundState objects to log
    ///   - vtxos: Optional array of all VTXOs to correlate with rounds
    ///   - context: Optional context string to identify when/why this logging occurred
    static func logRoundStates(_ rounds: [RoundState], vtxos: [Vtxo]? = nil, context: String? = nil) {
        let prefix = context.map { "[\($0)] " } ?? ""
        
        print("📊 \(prefix)Pending Rounds: \(rounds.count) total")
        
        if rounds.isEmpty {
            print("  ℹ️ No pending rounds")
            return
        }
        
        // Group locked VTXOs by their details
        let lockedVtxos = vtxos?.filter { if case .locked = $0.state { return true } else { return false } } ?? []
        let totalLockedSats = lockedVtxos.reduce(0) { $0 + $1.amountSats }
        
        if !lockedVtxos.isEmpty {
            print("  💰 Total locked in rounds: \(totalLockedSats) sats across \(lockedVtxos.count) VTXOs")
        }
        
        for (index, round) in rounds.enumerated() {
            let status = round.ongoing ? "🟢 ONGOING" : "⏸️ PAUSED"
            print("  \(index + 1). Round ID: \(round.id) | Status: \(status)")
            
            // If we have VTXO data, show details about locked VTXOs
            if !lockedVtxos.isEmpty {
                let roundLockedSats = lockedVtxos.reduce(0) { $0 + $1.amountSats }
                print("     └─ Locked VTXOs: \(lockedVtxos.count) (\(roundLockedSats) sats)")
                
                // Show individual VTXOs if there aren't too many
                if lockedVtxos.count <= 5 {
                    for vtxo in lockedVtxos {
                        let vtxoIdShort = String(vtxo.id.prefix(8)) + "..."
                        print("        • \(vtxoIdShort): \(vtxo.amountSats) sats, kind: \(vtxo.kind)")
                    }
                }
            }
        }
        
        // Explain paused rounds if we detect them
        let pausedRounds = rounds.filter { !$0.ongoing }
        if !pausedRounds.isEmpty {
            print("  ℹ️ Paused rounds: \(pausedRounds.count)")
            print("     Rounds may be paused if:")
            print("     • Waiting for server response")
            print("     • Network connectivity issues")
            print("     • Insufficient participants in round")
            print("     • Server is processing other rounds")
        }
    }
    
    /// Logs pending rounds from a BarkWalletProtocol instance with automatic error handling
    /// - Parameters:
    ///   - wallet: The wallet protocol instance
    ///   - context: Optional context string to identify when/why this logging occurred
    static func logPendingRounds(from wallet: any BarkWalletProtocol, context: String? = nil) async {
        do {
            let rounds = try await wallet.pendingRoundStates()
            
            // Try to fetch VTXOs for additional context
            var vtxos: [Vtxo]? = nil
            do {
                vtxos = try await wallet.allVtxos()
            } catch {
                // VTXO fetch failed, continue without it
            }
            
            logRoundStates(rounds, vtxos: vtxos, context: context)
        } catch {
            let prefix = context.map { "[\($0)] " } ?? ""
            print("⚠️ \(prefix)Could not fetch pending rounds: \(error)")
        }
    }
    
    /// Logs pending rounds from an FFI Wallet instance with automatic error handling
    /// - Parameters:
    ///   - wallet: The FFI Wallet instance
    ///   - context: Optional context string to identify when/why this logging occurred
    static func logPendingRounds(from wallet: Wallet, context: String? = nil) async {
        do {
            let rounds = try await wallet.pendingRoundStates()
            
            // Try to fetch VTXOs for additional context
            var vtxos: [Vtxo]? = nil
            do {
                vtxos = try await wallet.allVtxos()
            } catch {
                // VTXO fetch failed, continue without it
            }
            
            logRoundStates(rounds, vtxos: vtxos, context: context)
        } catch {
            let prefix = context.map { "[\($0)] " } ?? ""
            print("⚠️ \(prefix)Could not fetch pending rounds: \(error)")
        }
    }
}
