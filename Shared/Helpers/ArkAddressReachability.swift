//
//  ArkAddressReachability.swift
//  Arké
//
//  Whether this wallet's Ark server can deliver to an Ark address, as bark
//  judges it (same server, network and VTXO policy). Asked once per address
//  and remembered, so the synchronous typed-amount re-rank reads the same
//  verdict the asynchronous ranking obtained instead of asking bark again
//  (`Features/Foreign_Server_Ark_Address.md`).
//

import Foundation

@MainActor
final class ArkAddressReachability {
    /// Answers `true` / `false`, or `nil` when the answer is unknown
    /// (no wallet, no warm server connection, unparseable address)
    typealias Probe = (String) async -> Bool?

    private let probe: Probe
    /// Names the server the verdicts belong to; a change invalidates them
    /// without needing a wallet-lifecycle hook. Empty when unknown.
    private let scope: () -> String
    private var scopedVerdicts: [String: Bool] = [:]

    init(scope: @escaping () -> String = { "" }, probe: @escaping Probe) {
        self.scope = scope
        self.probe = probe
    }

    /// The remembered verdict, without asking. `nil` when never asked or
    /// the answer was unknown.
    func known(_ address: String) -> Bool? {
        scopedVerdicts[key(address)]
    }

    /// The verdict, asking the probe when none is remembered. Unknown
    /// answers are not remembered, so the next ranking asks again.
    @discardableResult
    func check(_ address: String) async -> Bool? {
        let key = key(address)
        if let verdict = scopedVerdicts[key] {
            return verdict
        }
        let verdict = await probe(address)
        if let verdict {
            scopedVerdicts[key] = verdict
        }
        return verdict
    }

    private func key(_ address: String) -> String {
        "\(scope())|\(address)"
    }
}
