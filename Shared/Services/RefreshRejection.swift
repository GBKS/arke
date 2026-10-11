//
//  RefreshRejection.swift
//  Arke
//
//  Pure logic for a server-rejected refresh request: telling a genuine
//  "already issued into a round" apart from inputs the server considers
//  spent, exited or banned, and remembering the latter so the app stops
//  re-submitting them on every launch (Refresh_Deduplication.md §9).
//

import Foundation
import Bark

/// Whether a scheduling error is the server refusing one or more inputs as
/// unusable (`UnusableInputs`; server `check_spendable`: exited, not in the
/// spendable state — including spent into an issued round — or banned).
///
/// Says nothing about *why*. Matched on message text because the FFI
/// collapses every `Bark.Error` into `BarkWalletFFIError.configurationError`
/// and the bindings carry a single `.Inner(message:)` case. Narrow by
/// design: anything unrecognised stays an ordinary error.
func isUnusableInputsRejection(_ error: Swift.Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("unusable_inputs") || message.contains("unusable inputs")
}

enum RefreshRejection {

    /// What a `unusable_inputs` rejection meant for the ids we submitted.
    enum Verdict: Equatable {
        /// Some requested ids *became* part of an in-flight refresh between
        /// our pre-call read and the call (the F5 race: the server issued the
        /// round meanwhile). Not a failure; nothing to remember — Guard C
        /// excludes those ids on the next check and the rest retry naturally.
        ///
        /// Ids that were already in the in-flight set *before* the call do
        /// not count: we submitted them anyway (Guard C's near-expiry valve
        /// lets expired VTXOs through), so the rejection says the pending
        /// entry is stale, not that a refresh is running — and treating it
        /// as in flight would restart the one-Failed-row-per-launch loop
        /// this change exists to stop.
        case inFlight(Set<String>)
        /// No requested id is in flight: the server considers the named ids
        /// spent, exited or banned. `precise` is true when the ids were read
        /// from the server message, false when the whole batch is recorded
        /// because none could be parsed.
        case rejected(ids: Set<String>, precise: Bool)
    }

    /// Classify a rejection.
    ///
    /// - Parameters:
    ///   - requested: the ids handed to `refreshVtxosDelegated`.
    ///   - beingRefreshedBefore: `vtxoIdsBeingRefreshed()` as read before
    ///     the call (the Guard C input).
    ///   - beingRefreshedAfter: the same set re-read *after* the post-error
    ///     refetch, so it reflects any round the server issued meanwhile.
    static func classify(
        requested: [String],
        beingRefreshedBefore: Set<String>,
        beingRefreshedAfter: Set<String>,
        serverMessage: String
    ) -> Verdict {
        let requestedSet = Set(requested)
        let newlyInFlight = beingRefreshedAfter.subtracting(beingRefreshedBefore)
        let inFlight = requestedSet.intersection(newlyInFlight)
        if !inFlight.isEmpty {
            return .inFlight(inFlight)
        }
        let named = parseVtxoIds(from: serverMessage).intersection(requestedSet)
        if !named.isEmpty {
            return .rejected(ids: named, precise: true)
        }
        return .rejected(ids: requestedSet, precise: false)
    }

    /// VTXO ids (`<64 hex>:<vout>`) mentioned anywhere in a server message.
    /// The server's `UnusableInputs` prints `unusable inputs: [id,id]`
    /// (server `error.rs`), so on the deployed release the offending ids are
    /// in the text; any other shape yields an empty set and the caller falls
    /// back to the whole batch.
    static func parseVtxoIds(from message: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{64}:[0-9]+") else {
            return []
        }
        let range = NSRange(message.startIndex..., in: message)
        let matches = regex.matches(in: message, range: range)
        return Set(matches.compactMap { match in
            Range(match.range, in: message).map { String(message[$0]).lowercased() }
        })
    }
}

/// Inputs the server rejected as unusable, remembered per id so neither
/// refresh path re-submits them for a while. Device-local; a cache of
/// server verdicts, not wallet state.
struct RefreshRejectionBackoff: Codable, Equatable {

    struct Entry: Codable, Equatable {
        let id: String
        let rejectedAt: Date
        /// Recorded because the whole batch was rejected and no id could be
        /// read from the message. Such an entry yields to the near-expiry
        /// valve; a precise one does not.
        let fromBatch: Bool
    }

    /// How long a verdict is honoured. Long enough that a stuck wallet adds
    /// one Failed row per day instead of one per launch; short enough that
    /// a wrong verdict (fail-open in-flight lookup, a lifted ban) never
    /// strands a VTXO.
    static let ttl: TimeInterval = 24 * 60 * 60

    private(set) var entries: [Entry] = []

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    // MARK: - Mutation

    /// Remember a verdict. Re-recording an id refreshes its timestamp.
    mutating func record(ids: Set<String>, precise: Bool, at now: Date) {
        entries.removeAll { ids.contains($0.id) }
        for id in ids.sorted() {
            entries.append(Entry(id: id, rejectedAt: now, fromBatch: !precise))
        }
    }

    /// Drop expired entries and entries for VTXOs no longer in the spendable
    /// set — the VTXO set changed, so the verdict is moot.
    mutating func prune(keeping spendableIds: Set<String>, now: Date) {
        let ttl = Self.ttl
        entries.removeAll { entry in
            !spendableIds.contains(entry.id) || now.timeIntervalSince(entry.rejectedAt) >= ttl
        }
    }

    // MARK: - Queries

    /// Whether a candidate must be held back from a refresh call.
    ///
    /// - A precise entry (the server named this id) always holds.
    /// - A batch entry yields inside the Guard C expiry valve
    ///   (0 < blocks-to-expiry ≤ `RefreshExclusion.hardExpiryThresholdBlocks`):
    ///   the server may have named a sibling, and a near-expiry renewal must
    ///   not wait a day on a guess. Past expiry the valve does not apply —
    ///   retrying a VTXO the server already refuses gains nothing.
    func shouldSkip(_ vtxo: Vtxo, currentBlockHeight: Int?, now: Date) -> Bool {
        shouldSkip(
            id: vtxo.id,
            expiryHeight: Int(vtxo.expiryHeight),
            currentBlockHeight: currentBlockHeight,
            now: now
        )
    }

    /// Same decision keyed on the id and expiry height alone, so the balance
    /// card (which holds `VTXOModel`s, not bark `Vtxo`s) applies exactly the
    /// rule the service applies. The former valve-blind `activeIds(now:)`
    /// over-reported held-back VTXOs and was removed
    /// (Refresh_Deduplication.md §10, D4).
    func shouldSkip(id: String, expiryHeight: Int, currentBlockHeight: Int?, now: Date) -> Bool {
        guard let entry = entries.first(where: { $0.id == id }),
              !isExpired(entry, now: now) else {
            return false
        }
        guard entry.fromBatch, let height = currentBlockHeight else {
            return true
        }
        let blocksUntilExpiry = expiryHeight - height
        let insideValve = blocksUntilExpiry > 0
            && blocksUntilExpiry <= RefreshExclusion.hardExpiryThresholdBlocks
        return !insideValve
    }

    /// Split candidates into those that may be submitted and those held back.
    func filter(
        _ vtxos: [Vtxo],
        currentBlockHeight: Int?,
        now: Date
    ) -> (kept: [Vtxo], skipped: [Vtxo]) {
        var kept: [Vtxo] = []
        var skipped: [Vtxo] = []
        for vtxo in vtxos {
            if shouldSkip(vtxo, currentBlockHeight: currentBlockHeight, now: now) {
                skipped.append(vtxo)
            } else {
                kept.append(vtxo)
            }
        }
        return (kept, skipped)
    }

    private func isExpired(_ entry: Entry, now: Date) -> Bool {
        now.timeIntervalSince(entry.rejectedAt) >= Self.ttl
    }

    // MARK: - Persistence

    /// Load from defaults; unreadable or missing data is an empty back-off
    /// (fail-open: the worst case is one more Failed row, as before).
    static func load(from defaults: UserDefaults, key: String) -> RefreshRejectionBackoff {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(RefreshRejectionBackoff.self, from: data) else {
            return RefreshRejectionBackoff()
        }
        return decoded
    }

    func save(to defaults: UserDefaults, key: String) {
        if entries.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }
}
