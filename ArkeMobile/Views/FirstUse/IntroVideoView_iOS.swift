//
//  IntroVideoView_iOS.swift
//  Arké
//
//  Created by Christoph on 01/20/26.
//

import SwiftUI
import ArkeUI

struct IntroVideoView_iOS: View {
    let onBack: (() -> Void)?
    let onContinue: (() -> Void)?
    let onSkip: (() -> Void)?
    let isMainnet: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPlaylist = false
    @State private var scrollPosition: Int? = 0
    @State private var isMuted = false
    @State private var isPaused = false

    private var currentVideoIndex: Int {
        scrollPosition ?? 0
    }
    
    // Playlist data (titles, asset names, subtitle timings) lives in
    // Shared/Models/IntroVideoLibrary.swift, shared with desktop
    private var videos: [IntroVideo] {
        IntroVideoLibrary.videos(isMainnet: isMainnet)
    }
    
    var body: some View {
        ZStack {
            // Full screen vertical paging feed: swipe up/down to move between
            // videos, with a rubber-band bounce at both ends
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        IntroVideoPlayer_iOS(
                            videoName: video.videoAssetName,
                            videoExtension: "mp4",
                            subtitles: video.subtitles,
                            isMuted: $isMuted,
                            // Only the settled page plays; neighbors preload
                            // paused at their first frame
                            isPaused: Binding(
                                get: { isPaused || scrollPosition != index },
                                set: { _ in }
                            ),
                            onVideoEnded: {
                                // Auto-advance to next video or call onContinue if last video
                                if index < videos.count - 1 {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                                        scrollPosition = index + 1
                                    }
                                } else if let onContinue {
                                    onContinue()
                                }
                            }
                        )
                        .containerRelativeFrame(.vertical)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPosition)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .accessibilityLabel(String(format: String(localized: "accessibility_video_player", defaultValue: "Video: %@"), videos[currentVideoIndex].title))
            .accessibilityAddTraits(.playsSound)
            .accessibilityHint(String(localized: "accessibility_video_has_captions", defaultValue: "Video includes captions"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if currentVideoIndex < videos.count - 1 {
                        scrollPosition = currentVideoIndex + 1
                    }
                case .decrement:
                    if currentVideoIndex > 0 {
                        scrollPosition = currentVideoIndex - 1
                    }
                @unknown default:
                    break
                }
            }
            
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
                        .accessibilityLabel(L10n.buttonBack)
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
                    .accessibilityLabel(String(localized: "action_video_menu", defaultValue: "Video menu"))
                    
                    Button {
                        isMuted.toggle()
                        
                        // Announce mute state change
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let announcement = isMuted ? 
                                String(localized: "accessibility_audio_muted", defaultValue: "Audio muted") : 
                                String(localized: "accessibility_audio_unmuted", defaultValue: "Audio unmuted")
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
                    .accessibilityLabel(isMuted ? String(localized: "action_unmute_audio", defaultValue: "Unmute audio") : String(localized: "action_mute_audio", defaultValue: "Mute audio"))
                    
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
                        .accessibilityLabel(String(localized: "button_skip", defaultValue: "Skip"))
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
                                    // No animation: distant jumps shouldn't
                                    // flip through every page in between
                                    scrollPosition = index
                                    showPlaylist = false
                                }
                            }
                        }
                        .padding(16)
                    }
                    .background(Color.Arke.gold4.opacity(0.98))
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
        .background(Color.Arke.gold4)
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
                        Text(String(localized: "label_now_playing", defaultValue: "Now Playing"))
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
            String(format: String(localized: "accessibility_video_now_playing", defaultValue: "Now playing: %@"), video.title) :
            String(format: String(localized: "accessibility_video_item", defaultValue: "Video %1$lld: %2$@"), index + 1, video.title))
        .accessibilityHint(String(localized: "accessibility_play_video_hint", defaultValue: "Double tap to play this video"))
        .accessibilityAddTraits(isCurrentlyPlaying ? [.isButton, .isSelected] : .isButton)
    }
}
