//
//  PaymentFeedback.swift
//  Arké
//
//  Sound and haptics for the moment a payment completes.
//

import Foundation
import AVFoundation
import OSLog
#if os(iOS)
import UIKit
#endif

/// Plays the "payment sent" and "payment received" sounds with a matching
/// haptic, and the error haptic for a failed send.
///
/// The two AAC files (`.m4a`) live in `Shared/Images` next to the videos and are decoded
/// once, then replayed from the start on every call. The audio session stays
/// `.ambient`, the category the looping video player already sets: sounds
/// mix with whatever else is playing and go silent with the ring switch.
///
/// A receive can be seen by more than one view at once (the Lightning
/// invoice sheet over the Receive tab), so `paymentReceived(movementId:)`
/// plays once per movement id.
@MainActor
final class PaymentFeedback {
    static let shared = PaymentFeedback()

    enum Sound: String, CaseIterable, Sendable {
        case sent = "payment-sent"
        case received = "payment-received"
    }

    private enum Haptic {
        case success
        case error
    }

    private let player = SoundPlayer()
    private var announcedMovementIds: [UInt32] = []
    private let announcedMovementLimit = 16

    private init() {}

    /// Decode both files ahead of time so the first play is not late.
    func preload() {
        Task { await player.preload() }
    }

    func paymentSent() {
        Task { await player.play(.sent) }
        notify(.success)
    }

    func paymentFailed() {
        notify(.error)
    }

    /// Plays the received sound and haptic unless this movement was already
    /// announced. Returns whether anything played.
    @discardableResult
    func paymentReceived(movementId: UInt32) -> Bool {
        guard !announcedMovementIds.contains(movementId) else { return false }
        announcedMovementIds.append(movementId)
        if announcedMovementIds.count > announcedMovementLimit {
            announcedMovementIds.removeFirst(announcedMovementIds.count - announcedMovementLimit)
        }
        Task { await player.play(.received) }
        notify(.success)
        return true
    }

    // MARK: - Private

    private func notify(_ haptic: Haptic) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        switch haptic {
        case .success:
            generator.notificationOccurred(.success)
        case .error:
            generator.notificationOccurred(.error)
        }
        #endif
    }
}

/// Owns the audio players off the main thread. `prepareToPlay()` and the
/// first `play()` activate the audio session synchronously, which the
/// main-thread checker flags as a UI stall, so every player call lands here.
private actor SoundPlayer {
    private static let fileExtension = "m4a"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "PaymentFeedback")
    private var players: [PaymentFeedback.Sound: AVAudioPlayer] = [:]
    private var hasConfiguredSession = false

    func preload() {
        configureSessionIfNeeded()
        for sound in PaymentFeedback.Sound.allCases {
            _ = player(for: sound)
        }
    }

    func play(_ sound: PaymentFeedback.Sound) {
        configureSessionIfNeeded()
        guard let player = player(for: sound) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for sound: PaymentFeedback.Sound) -> AVAudioPlayer? {
        if let player = players[sound] {
            return player
        }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: Self.fileExtension) else {
            logger.error("Missing sound resource \(sound.rawValue).\(Self.fileExtension)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[sound] = player
            return player
        } catch {
            logger.error("Could not load \(sound.rawValue).\(Self.fileExtension): \(error.localizedDescription)")
            return nil
        }
    }

    /// `.ambient` mixes with other audio and respects the ring switch, the
    /// same category `LoopingVideoPlayer_iOS` sets.
    private func configureSessionIfNeeded() {
        #if os(iOS)
        guard !hasConfiguredSession else { return }
        hasConfiguredSession = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            logger.error("Could not set audio session category: \(error.localizedDescription)")
        }
        #endif
    }
}
