//
//  IntroVideoView_iOS.swift
//  Arké
//
//  Created by Christoph on 01/20/26.
//

import SwiftUI
import ArkeUI

struct IntroVideo: Identifiable {
    let id = UUID()
    let title: String
    let thumbnailName: String
    let videoAssetName: String
    let subtitles: [VideoSubtitle]
}

struct IntroVideoView_iOS: View {
    let onBack: (() -> Void)?
    let onContinue: (() -> Void)?
    let onSkip: (() -> Void)?
    let isMainnet: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPlaylist = false
    @State private var currentVideoIndex = 0
    @State private var isMuted = false
    @State private var isPaused = false
    
    // Shared videos (used by both signet and mainnet)
    private let sharedVideo1 = IntroVideo(
        title: "Welcome",
        thumbnailName: "1-intro-v2-small-image",
        videoAssetName: "1-intro-v2-small",
        subtitles: [
            VideoSubtitle(startTime: 0.020, endTime: 1.520, text: "Hey, welcome to Arké."),
            VideoSubtitle(startTime: 2.420, endTime: 4.100, text: "You're about to try something new."),
            VideoSubtitle(startTime: 4.760, endTime: 7.060, text: "A bitcoin wallet built for real payments."),
            VideoSubtitle(startTime: 7.860, endTime: 10.200, text: "Fast, cheap, and fully yours."),
            VideoSubtitle(startTime: 11.260, endTime: 15.200, text: "Before you dive in, my friends are going to walk you through how things work.")
        ]
    )
    
    private let sharedVideo3 = IntroVideo(
        title: "It's yours",
        thumbnailName: "3-ownership-v2-small-image",
        videoAssetName: "3-ownership-v2-small",
        subtitles: [
            VideoSubtitle(startTime: 0.020, endTime: 2.260, text: "This wallet belongs entirely to you."),
            VideoSubtitle(startTime: 2.850, endTime: 6.560, text: "No accounts, no logins, no company holding your funds."),
            VideoSubtitle(startTime: 7.360, endTime: 9.220, text: "You'll get a 12 word recovery phrase,"),
            VideoSubtitle(startTime: 9.670, endTime: 12.740, text: "and your wallet will back up data to iCloud automatically."),
            VideoSubtitle(startTime: 13.520, endTime: 15.260, text: "You need both to restore your wallet."),
            VideoSubtitle(startTime: 15.850, endTime: 19.840, text: "So keep your phrase somewhere safe and stay signed in to iCloud.")
        ]
    )
    
    private let sharedVideo4 = IntroVideo(
        title: "Instant payments",
        thumbnailName: "4-speed-small-image",
        videoAssetName: "4-speed-small",
        subtitles: [
            VideoSubtitle(startTime: 0.020, endTime: 2.720, text: "So why Arké instead of a regular Bitcoin wallet?"),
            VideoSubtitle(startTime: 4.100, endTime: 5.560, text: "Normally Bitcoin payments are slow."),
            VideoSubtitle(startTime: 6.600, endTime: 8.780, text: "You wait for confirmations, fees add up."),
            VideoSubtitle(startTime: 9.320, endTime: 10.660, text: "It's not great for grabbing coffee."),
            VideoSubtitle(startTime: 11.760, endTime: 12.620, text: "Arké fixes that."),
            VideoSubtitle(startTime: 13.520, endTime: 15.820, text: "Payments arrive in seconds, fees are almost nothing."),
            VideoSubtitle(startTime: 16.580, endTime: 18.400, text: "Same Bitcoin, just a better experience.")
        ]
    )
    
    private let sharedVideo5 = IntroVideo(
        title: "Two balances",
        thumbnailName: "5-two-balances-v2-small-image",
        videoAssetName: "5-two-balances-v2-small",
        subtitles: [
            VideoSubtitle(startTime: 0.020, endTime: 3.780, text: "One thing to know, your wallet has two balances."),
            VideoSubtitle(startTime: 5.000, endTime: 6.520, text: "Savings is for holding."),
            VideoSubtitle(startTime: 7.460, endTime: 10.900, text: "Fully independent, nothing to rely on but yourself."),
            VideoSubtitle(startTime: 12.240, endTime: 14.380, text: "Spending is for everyday use."),
            VideoSubtitle(startTime: 15.060, endTime: 17.080, text: "Instant payments, tiny fees."),
            VideoSubtitle(startTime: 18.180, endTime: 21.500, text: "It uses a coordination server to make things fast."),
            VideoSubtitle(startTime: 22.400, endTime: 26.240, text: "But that server can never access your money or see your balance."),
            VideoSubtitle(startTime: 27.140, endTime: 30.280, text: "You can move funds between them whenever you like.")
        ]
    )
    
    // Network-specific videos
    private let video2Signet = IntroVideo(
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
    
    private let video2Mainnet = IntroVideo(
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
    
    private let video6Signet = IntroVideo(
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
    
    private let video6Mainnet = IntroVideo(
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
    
    private var videos: [IntroVideo] {
        [
            sharedVideo1,
            isMainnet ? video2Mainnet : video2Signet,
            sharedVideo3,
            sharedVideo4,
            sharedVideo5,
            isMainnet ? video6Mainnet : video6Signet
        ]
    }
    
    var body: some View {
        ZStack {
            // Full screen video player
            IntroVideoPlayer_iOS(
                videoName: videos[currentVideoIndex].videoAssetName,
                videoExtension: "mp4",
                subtitles: videos[currentVideoIndex].subtitles,
                isMuted: $isMuted,
                isPaused: $isPaused,
                onVideoEnded: {
                    // Auto-advance to next video or call onContinue if last video
                    if currentVideoIndex < videos.count - 1 {
                        currentVideoIndex += 1
                    } else if let onContinue {
                        onContinue()
                    }
                }
            )
            .id(currentVideoIndex) // Force recreation when video changes
            .ignoresSafeArea()
            .accessibilityLabel(String(format: String(localized: "accessibility_video_player"), videos[currentVideoIndex].title))
            .accessibilityAddTraits(.playsSound)
            .accessibilityHint(String(localized: "accessibility_video_has_captions"))
            
            // Top toolbar overlay
            VStack {
                HStack {
                    if let onBack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .colorScheme(.dark)
                        .tint(Color.Arke.gold)
                        .accessibilityLabel("button_back")
                    }
                    
                    Spacer()
                    
                    Button {
                        showPlaylist.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .colorScheme(.dark)
                    .tint(Color.Arke.gold)
                    .accessibilityLabel("action_video_menu")
                    
                    Button {
                        isMuted.toggle()
                        
                        // Announce mute state change
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let announcement = isMuted ? 
                                String(localized: "accessibility_audio_muted") : 
                                String(localized: "accessibility_audio_unmuted")
                            UIAccessibility.post(notification: .announcement, argument: announcement)
                        }
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .colorScheme(.dark)
                    .tint(Color.Arke.gold)
                    .accessibilityLabel(isMuted ? String(localized: "action_unmute_audio") : String(localized: "action_mute_audio"))
                    
                    if let onSkip {
                        Button {
                            onSkip()
                        } label: {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 20))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .colorScheme(.dark)
                        .tint(Color.Arke.gold)
                        .accessibilityLabel("button_skip")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, safeAreaInsets.top + 8)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
            }
            
            // Playlist overlay
            if showPlaylist {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showPlaylist = false
                    }
                
                VStack(spacing: 0) {
                    // Video list
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                                VideoListItem(
                                    video: video,
                                    index: index,
                                    isCurrentlyPlaying: index == currentVideoIndex
                                ) {
                                    currentVideoIndex = index
                                    showPlaylist = false
                                }
                            }
                        }
                        .padding(16)
                    }
                    .background(Color.Arke.gold3.opacity(0.98))
                }
                .frame(maxWidth: 400)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .shadow(color: .black.opacity(0.5), radius: 20)
                .padding(.horizontal, 16)
                .padding(.vertical, safeAreaInsets.top + 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold3)
        .ignoresSafeArea()
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: showPlaylist)
        .onChange(of: showPlaylist) { _, newValue in
            isPaused = newValue
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

struct VideoListItem: View {
    let video: IntroVideo
    let index: Int
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 15) {
                // Thumbnail
                ZStack {
                    // Background image
                    Image(video.thumbnailName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                    
                    // Overlay gradient for better icon visibility
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            LinearGradient(
                                colors: [.black.opacity(0.4), .clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    // Play indicator or video number
                    if isCurrentlyPlaying {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.Arke.gold)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                }
                
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    if isCurrentlyPlaying {
                        Text("label_now_playing")
                            .font(.footnote)
                            .foregroundStyle(Color.Arke.gold)
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isCurrentlyPlaying ? Color.Arke.gold.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCurrentlyPlaying ? 
            String(format: String(localized: "accessibility_video_now_playing"), video.title) :
            String(format: String(localized: "accessibility_video_item"), index + 1, video.title))
        .accessibilityHint(String(localized: "accessibility_play_video_hint"))
        .accessibilityAddTraits(isCurrentlyPlaying ? [.isButton, .isSelected] : .isButton)
    }
}
