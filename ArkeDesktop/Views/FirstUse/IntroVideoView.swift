//
//  IntroVideoView.swift
//  Arké
//
//  Created by Christoph on 08/11/26.
//
//  macOS take on IntroVideoView_iOS: the portrait videos (720x1280) sit in
//  the left column, matching the FirstUseView cover layout, and the playlist
//  mobile hides behind a hamburger overlay is permanent content on the right.
//  Playlist data comes from the shared IntroVideoLibrary so subtitle timings
//  can't drift between platforms.
//

import SwiftUI
import ArkeUI
import Accessibility

struct IntroVideoView: View {
    let onBack: (() -> Void)?
    let onContinue: (() -> Void)?
    let onSkip: (() -> Void)?
    let isMainnet: Bool

    @State private var currentVideoIndex = 0
    @State private var isMuted = false
    @State private var isPaused = false

    private var videos: [IntroVideo] {
        IntroVideoLibrary.videos(isMainnet: isMainnet)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left column - video with subtitles and tap-to-pause
            IntroVideoPlayer(
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
            .accessibilityLabel(String(format: String(localized: "accessibility_video_player"), videos[currentVideoIndex].title))
            .accessibilityAddTraits(.playsSound)
            .accessibilityHint(String(localized: "accessibility_video_has_captions"))
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Button {
                    isMuted.toggle()

                    // Announce mute state change
                    let announcement = isMuted ?
                        String(localized: "accessibility_audio_muted") :
                        String(localized: "accessibility_audio_unmuted")
                    AccessibilityNotification.Announcement(announcement).post()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .tint(Color.Arke.gold)
                .accessibilityLabel(isMuted ? String(localized: "action_unmute_audio") : String(localized: "action_mute_audio"))
                .padding(20)
            }

            // Right column - playlist and skip
            VStack(spacing: 30) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            VideoListItem(
                                video: video,
                                index: index,
                                isCurrentlyPlaying: index == currentVideoIndex
                            ) {
                                currentVideoIndex = index
                            }
                        }
                    }
                }

                if let onSkip {
                    Button {
                        onSkip()
                    } label: {
                        Text("button_skip")
                            .font(.system(.title2, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .tint(Color.Arke.gold)
                .accessibilityLabel("button_back")
                .padding(20)
            }
        }
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
