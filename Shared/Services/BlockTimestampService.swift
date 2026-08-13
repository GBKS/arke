//
//  BlockTimestampService.swift
//  Arké
//
//  Resolves block timestamps by hash from Esplora. Bark's BlockRef carries
//  height + hash but no block time, and onchain transaction dates come from
//  the block time — see Shared/Docs/Features/BDK_Transaction_Reader_Removal.md.
//

import Foundation

/// Fetches block timestamps from Esplora, with an in-memory cache.
/// Block timestamps are immutable, so cache entries never expire; a failed
/// fetch simply retries on the next request.
actor BlockTimestampService {

    private let esploraBaseURL: String
    private let session: URLSession
    private var cache: [String: UInt64] = [:]

    init(esploraBaseURL: String, session: URLSession = .shared) {
        self.esploraBaseURL = esploraBaseURL.hasSuffix("/")
            ? String(esploraBaseURL.dropLast())
            : esploraBaseURL
        self.session = session
    }

    /// Unix timestamp of the block with the given hash, or nil if it can't
    /// be fetched right now.
    func timestamp(forBlockHash hash: String) async -> UInt64? {
        if let cached = cache[hash] {
            return cached
        }

        guard let url = URL(string: "\(esploraBaseURL)/block/\(hash)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            let block = try JSONDecoder().decode(BlockHeader.self, from: data)
            cache[hash] = block.timestamp
            return block.timestamp
        } catch {
            return nil
        }
    }

    /// Resolve timestamps for a set of block hashes. Hashes that can't be
    /// resolved are absent from the result.
    func timestamps(forBlockHashes hashes: some Sequence<String> & Sendable) async -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        for hash in hashes {
            if let timestamp = await timestamp(forBlockHash: hash) {
                result[hash] = timestamp
            }
        }
        return result
    }

    private struct BlockHeader: Decodable {
        let timestamp: UInt64
    }
}
