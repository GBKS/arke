//
//  IntroVideoLibrary.swift
//  Arké
//
//  Created by Christoph on 08/11/26.
//

import Foundation

// MARK: - Subtitle Model

struct VideoSubtitle: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    func isActive(at time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }
}

// MARK: - Intro Video Model

struct IntroVideo: Identifiable {
    let id = UUID()
    let title: String
    let thumbnailName: String
    let videoAssetName: String
    let subtitles: [VideoSubtitle]
}

// MARK: - Intro Video Library

/// The onboarding intro video playlist, shared between mobile and desktop
/// so titles, asset names, and subtitle timings can't drift apart.
enum IntroVideoLibrary {

    /// The full playlist in playback order, with network-specific variants
    /// for videos 2 and 6.
    static func videos(isMainnet: Bool) -> [IntroVideo] {
        [
            sharedVideo1,
            isMainnet ? video2Mainnet : video2Signet,
            sharedVideo3,
            sharedVideo4,
            sharedVideo5,
            isMainnet ? video6Mainnet : video6Signet
        ]
    }

    // Shared videos (used by both signet and mainnet)
    private static let sharedVideo1 = IntroVideo(
        title: "Welcome",
        thumbnailName: "1-intro-v2-small-image",
        videoAssetName: "1-intro-v3-small",
        subtitles: [
            VideoSubtitle(startTime: 0.001, endTime: 2.240, text: "Hey, welcome to Arké."),
            VideoSubtitle(startTime: 2.240, endTime: 4.320, text: "You're about to try something new."),
            VideoSubtitle(startTime: 4.320, endTime: 7.440, text: "A bitcoin wallet built for real payments."),
            VideoSubtitle(startTime: 7.440, endTime: 10.480, text: "Fast, cheap, and fully yours."),
            VideoSubtitle(startTime: 10.480, endTime: 14.760, text: "Before you dive in, my friends are going to walk you through how things work."),
            VideoSubtitle(startTime: 14.760, endTime: 16.840, text: "This'll only take a couple minutes.")
        ]
    )

    private static let sharedVideo3 = IntroVideo(
        title: "It's yours",
        thumbnailName: "3-ownership-v2-small-image",
        videoAssetName: "3-ownership-v3-small",
        subtitles: [
            VideoSubtitle(startTime: 0.001, endTime: 2.640, text: "This wallet belongs entirely to you."),
            VideoSubtitle(startTime: 2.640, endTime: 5.120, text: "No accounts, no logins."),
            VideoSubtitle(startTime: 5.120, endTime: 6.560, text: "You hold the keys."),
            VideoSubtitle(startTime: 6.560, endTime: 9.040, text: "You'll get a 12-word recovery phrase."),
            VideoSubtitle(startTime: 9.040, endTime: 12.400, text: "Both your phrase and your wallet data back up to iCloud"),
            VideoSubtitle(startTime: 12.560, endTime: 13.680, text: "automatically."),
            VideoSubtitle(startTime: 13.460, endTime: 16.340, text: "To restore on a new device, you'll need both, so"),
            VideoSubtitle(startTime: 16.500, endTime: 17.220, text: "stay signed into"),
            VideoSubtitle(startTime: 17.380, endTime: 19.300, text: "iCloud and write your phrase down"),
            VideoSubtitle(startTime: 19.460, endTime: 21.220, text: "too, just in case.")
        ]
    )

    private static let sharedVideo4 = IntroVideo(
        title: "Instant payments",
        thumbnailName: "4-speed-small-image",
        videoAssetName: "4-speed-v2-small",
        subtitles: [
            VideoSubtitle(startTime: 0.001, endTime: 1.760, text: "Okay, security sorted."),
            VideoSubtitle(startTime: 1.760, endTime: 2.880, text: "So why Arké"),
            VideoSubtitle(startTime: 3.040, endTime: 5.040, text: "instead of a regular Bitcoin wallet?"),
            VideoSubtitle(startTime: 5.040, endTime: 7.120, text: "Normally Bitcoin payments are slow."),
            VideoSubtitle(startTime: 7.120, endTime: 9.920, text: "You wait for confirmations, fees add up."),
            VideoSubtitle(startTime: 9.860, endTime: 11.700, text: "It is not great for grabbing coffee."),
            VideoSubtitle(startTime: 11.700, endTime: 13.139, text: "Arké fixes that."),
            VideoSubtitle(startTime: 13.139, endTime: 14.980, text: "Payments arrive in seconds."),
            VideoSubtitle(startTime: 14.980, endTime: 16.580, text: "Fees are almost nothing."),
            VideoSubtitle(startTime: 16.580, endTime: 19.540, text: "Same Bitcoin, just a better experience.")
        ]
    )

    private static let sharedVideo5 = IntroVideo(
        title: "Two balances",
        thumbnailName: "5-two-balances-v2-small-image",
        videoAssetName: "5-two-balances-v3-small",
        subtitles: [
            VideoSubtitle(startTime: 0.001, endTime: 1.280, text: "One thing to know, your"),
            VideoSubtitle(startTime: 1.440, endTime: 3.360, text: "wallet has two balances."),
            VideoSubtitle(startTime: 3.360, endTime: 5.280, text: "Savings is for holding, fully"),
            VideoSubtitle(startTime: 5.440, endTime: 8.480, text: "independent, nothing to rely on but yourself."),
            VideoSubtitle(startTime: 8.240, endTime: 10.640, text: "Spending is for everyday use."),
            VideoSubtitle(startTime: 10.640, endTime: 12.480, text: "A server keeps it fast."),
            VideoSubtitle(startTime: 12.480, endTime: 16.560, text: "As long as you open the app now and then, it can't touch your funds on its own."),
            VideoSubtitle(startTime: 16.560, endTime: 17.920, text: "Turn on notifications"),
            VideoSubtitle(startTime: 18.080, endTime: 18.400, text: "and we will"),
            VideoSubtitle(startTime: 18.560, endTime: 20.160, text: "remind you when it's time."),
            VideoSubtitle(startTime: 20.160, endTime: 22.880, text: "You can move funds to savings anytime.")
        ]
    )

    // Network-specific videos
    private static let video2Signet = IntroVideo(
        title: "You're early",
        thumbnailName: "2-testing-cherry-blossom-v2-small-image",
        videoAssetName: "2-testing-cherry-blossom-v2-small",
        subtitles: [
            VideoSubtitle(startTime: 0.020, endTime: 1.300, text: "First, a heads up."),
            VideoSubtitle(startTime: 1.900, endTime: 2.280, text: "You're early."),
            VideoSubtitle(startTime: 3.000, endTime: 4.200, text: "Arké is still in testing."),
            VideoSubtitle(startTime: 4.900, endTime: 6.320, text: "The Bitcoin in here isn't real."),
            VideoSubtitle(startTime: 6.660, endTime: 7.320, text: "It's play money."),
            VideoSubtitle(startTime: 8.080, endTime: 10.080, text: "That means you can try everything without risk."),
            VideoSubtitle(startTime: 10.780, endTime: 12.720, text: "It also means things might break sometimes."),
            VideoSubtitle(startTime: 13.460, endTime: 13.960, text: "That's fine."),
            VideoSubtitle(startTime: 14.500, endTime: 15.560, text: "That's what testing is for.")
        ]
    )

    private static let video2Mainnet = IntroVideo(
        title: "You're early",
        thumbnailName: "2-testing-cherry-blossom-v2-small-image",
        videoAssetName: "2-testing-cherry-blossom-v2-mainnet-small",
        subtitles: [
            VideoSubtitle(startTime: 0.001, endTime: 2.640, text: "First, a heads up, you're early."),
            VideoSubtitle(startTime: 2.640, endTime: 4.400, text: "Arké is still new."),
            VideoSubtitle(startTime: 4.400, endTime: 6.080, text: "This is real Bitcoin."),
            VideoSubtitle(startTime: 6.080, endTime: 8.480, text: "Your money, your responsibility"),
            VideoSubtitle(startTime: 8.559, endTime: 12.320, text: "We've tested thoroughly, but new things can have rough edges."),
            VideoSubtitle(startTime: 12.320, endTime: 16.320, text: "Start small, get comfortable, then grow from there."),
            VideoSubtitle(startTime: 16.320, endTime: 19.920, text: "Being early means you help shape what this becomes")
        ]
    )

    private static let video6Signet = IntroVideo(
        title: "Get started",
        thumbnailName: "6-get-started-small-image",
        videoAssetName: "6-get-started-small",
        subtitles: [
            VideoSubtitle(startTime: 0.020, endTime: 1.440, text: "That's really all you need to know."),
            VideoSubtitle(startTime: 2.620, endTime: 7.800, text: "Once you're set up, grab some free test Bitcoin and try your first payment."),
            VideoSubtitle(startTime: 8.660, endTime: 9.460, text: "See how it feels."),
            VideoSubtitle(startTime: 10.340, endTime: 11.080, text: "Break things."),
            VideoSubtitle(startTime: 11.780, endTime: 12.820, text: "Let us know what's broken."),
            VideoSubtitle(startTime: 13.740, endTime: 15.240, text: "You're not just a user here."),
            VideoSubtitle(startTime: 15.940, endTime: 17.420, text: "You're helping us build this."),
            VideoSubtitle(startTime: 18.460, endTime: 18.720, text: "Ready?")
        ]
    )

    private static let video6Mainnet = IntroVideo(
        title: "Get started",
        thumbnailName: "6-get-started-small-image",
        videoAssetName: "6-get-started-mainnet-small",
        subtitles: [
            VideoSubtitle(startTime: 0.001, endTime: 2.080, text: "That's really all you need to know."),
            VideoSubtitle(startTime: 2.080, endTime: 6.560, text: "Once you're set up, receive some Bitcoin and try your first payment."),
            VideoSubtitle(startTime: 6.560, endTime: 10.480, text: "Even a small amount is enough to feel how it works."),
            VideoSubtitle(startTime: 10.480, endTime: 12.240, text: "Notice something off?"),
            VideoSubtitle(startTime: 12.340, endTime: 13.540, text: "Tell us."),
            VideoSubtitle(startTime: 13.540, endTime: 15.140, text: "We're listening."),
            VideoSubtitle(startTime: 15.140, endTime: 17.220, text: "You're not just a user here."),
            VideoSubtitle(startTime: 17.220, endTime: 19.460, text: "You're one of the first."),
            VideoSubtitle(startTime: 19.460, endTime: 20.420, text: "Ready?")
        ]
    )
}
