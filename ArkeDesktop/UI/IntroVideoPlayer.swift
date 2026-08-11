//
//  IntroVideoPlayer.swift
//  Arké
//
//  Created by Christoph on 08/11/26.
//
//  macOS port of IntroVideoPlayer_iOS; uses the shared VideoSubtitle model.
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

// MARK: - Video Player ViewModel

@MainActor
class IntroVideoPlayerViewModel: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentSubtitle: String?
    @Published var hasEnded: Bool = false
    @Published var isMuted: Bool = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    let videoName: String
    let videoExtension: String
    let subtitles: [VideoSubtitle]
    let autoPlay: Bool
    let onVideoEnded: () -> Void

    init(
        videoName: String,
        videoExtension: String = "mp4",
        subtitles: [VideoSubtitle] = [],
        autoPlay: Bool = true,
        onVideoEnded: @escaping () -> Void = {}
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.subtitles = subtitles
        self.autoPlay = autoPlay
        self.onVideoEnded = onVideoEnded
    }

    func setupPlayer() -> AVPlayer? {
        guard let videoURL = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            print("❌ Video not found: \(videoName).\(videoExtension)")
            return nil
        }

        let player = AVPlayer(url: videoURL)
        self.player = player

        // Add periodic time observer for subtitle updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.updateSubtitle(for: time.seconds)
            }
        }

        // Observe when video ends
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.videoDidEnd()
            }
        }

        if autoPlay {
            player.play()
            // Defer state change to avoid "Publishing changes from within view updates" warning
            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = true
            }
        }

        return player
    }

    func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if hasEnded {
                player.seek(to: .zero)
                hasEnded = false
            }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func toggleMute() {
        guard let player = player else { return }
        isMuted.toggle()
        player.isMuted = isMuted
    }

    func setMuted(_ muted: Bool) {
        guard let player = player else { return }
        isMuted = muted
        player.isMuted = muted
    }

    private func updateSubtitle(for time: TimeInterval) {
        // Find active subtitle at current time
        let activeSubtitle = subtitles.first { $0.isActive(at: time) }
        currentSubtitle = activeSubtitle?.text
    }

    private func videoDidEnd() {
        hasEnded = true
        isPlaying = false
        currentSubtitle = nil
        onVideoEnded()
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        player?.pause()
        player = nil
    }
}

// MARK: - Video Player View

struct IntroVideoPlayer: View {
    @StateObject private var viewModel: IntroVideoPlayerViewModel
    @Binding var isMuted: Bool
    @Binding var isPaused: Bool
    private let subtitleBottomPadding: CGFloat

    init(
        videoName: String,
        videoExtension: String = "mp4",
        subtitles: [VideoSubtitle] = [],
        autoPlay: Bool = true,
        subtitleBottomPadding: CGFloat = 60,
        isMuted: Binding<Bool> = .constant(false),
        isPaused: Binding<Bool> = .constant(false),
        onVideoEnded: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: IntroVideoPlayerViewModel(
            videoName: videoName,
            videoExtension: videoExtension,
            subtitles: subtitles,
            autoPlay: autoPlay,
            onVideoEnded: onVideoEnded
        ))
        _isMuted = isMuted
        _isPaused = isPaused
        self.subtitleBottomPadding = subtitleBottomPadding
    }

    var body: some View {
        ZStack {
            // Video player
            IntroVideoPlayerView(viewModel: viewModel)
                .ignoresSafeArea()

            // Play/pause/replay indicator
            if !viewModel.isPlaying {
                Image(systemName: viewModel.hasEnded ? "arrow.counterclockwise" : "play.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .frame(width: 75, height: 75)
                    .background(
                        Circle()
                            .fill(.black.opacity(0.75))
                            .shadow(color: .black.opacity(0.3), radius: 10)
                    )
                    .transition(.opacity.combined(with: .scale))
            }

            // Subtitle overlay
            if let subtitle = viewModel.currentSubtitle {
                VStack {
                    Spacer()

                    Text(subtitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.75))
                                .shadow(color: .black.opacity(0.3), radius: 8)
                        )
                        .padding(.horizontal, 40)
                        .padding(.bottom, subtitleBottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Tap overlay for play/pause; kept topmost so the indicator and
            // subtitles below never swallow taps
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.togglePlayPause()
                }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isPlaying)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentSubtitle)
        .onChange(of: isMuted) { _, newValue in
            viewModel.setMuted(newValue)
        }
        .onChange(of: isPaused) { _, newValue in
            if newValue {
                viewModel.pause()
            } else {
                viewModel.play()
            }
        }
        .onAppear {
            viewModel.setMuted(isMuted)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

// MARK: - NSViewRepresentable for AVPlayer

private struct IntroVideoPlayerView: NSViewRepresentable {
    @ObservedObject var viewModel: IntroVideoPlayerViewModel

    func makeNSView(context: Context) -> VideoPlayerNSView {
        let view = VideoPlayerNSView()
        if let player = viewModel.setupPlayer() {
            view.configure(with: player)
        }
        return view
    }

    func updateNSView(_ nsView: VideoPlayerNSView, context: Context) {
        // Updates handled by view model
    }

    class VideoPlayerNSView: NSView {
        private var playerLayer: AVPlayerLayer?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.wantsLayer = true
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.wantsLayer = true
        }

        func configure(with player: AVPlayer) {
            playerLayer = AVPlayerLayer(player: player)

            guard let playerLayer = playerLayer else { return }

            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = bounds
            layer?.addSublayer(playerLayer)
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }
    }
}
