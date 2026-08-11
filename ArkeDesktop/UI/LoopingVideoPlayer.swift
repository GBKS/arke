//
//  LoopingVideoPlayer.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import AVKit
import AVFoundation

struct LoopingVideoPlayer: NSViewRepresentable {
    let videoName: String
    let videoExtension: String
    let videoGravity: AVLayerVideoGravity
    let autoPlay: Bool
    let showErrorIndicator: Bool
    let loops: Bool
    let onCompletion: (() -> Void)?

    /// Creates a looping video player
    /// - Parameters:
    ///   - videoName: Name of the video file in the app bundle
    ///   - videoExtension: File extension (e.g., "mp4", "mov")
    ///   - videoGravity: How the video should be scaled within the view bounds
    ///   - autoPlay: Whether to start playing automatically
    ///   - showErrorIndicator: Whether to show a red background if video fails to load
    ///   - loops: Whether the video should loop continuously (default: true)
    ///   - onCompletion: Optional callback when video completes (only called if loops is false)
    init(
        videoName: String,
        videoExtension: String,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoPlay: Bool = true,
        showErrorIndicator: Bool = true,
        loops: Bool = true,
        onCompletion: (() -> Void)? = nil
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.videoGravity = videoGravity
        self.autoPlay = autoPlay
        self.showErrorIndicator = showErrorIndicator
        self.loops = loops
        self.onCompletion = onCompletion
    }

    func makeNSView(context: Context) -> PlayerView {
        let playerView = PlayerView()
        playerView.setupVideo(
            name: videoName,
            extension: videoExtension,
            videoGravity: videoGravity,
            autoPlay: autoPlay,
            showErrorIndicator: showErrorIndicator,
            loops: loops,
            onCompletion: onCompletion
        )
        return playerView
    }
    
    func updateNSView(_ nsView: PlayerView, context: Context) {
        // Updates are handled internally by PlayerView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        // Coordinator can be used for future enhancements like playback control
    }

class PlayerView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopingObserver: NSObjectProtocol?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }
    
    func setupVideo(
        name: String,
        extension: String,
        videoGravity: AVLayerVideoGravity,
        autoPlay: Bool,
        showErrorIndicator: Bool,
        loops: Bool,
        onCompletion: (() -> Void)?
    ) {
        // Load video from bundle
        guard let videoURL = Bundle.main.url(forResource: name, withExtension: `extension`) else {
            if showErrorIndicator {
                // Add a colored background to make it obvious the video didn't load
                self.layer?.backgroundColor = NSColor.red.cgColor
            }
            return
        }

        player = AVPlayer(url: videoURL)

        // Set the player volume to 0 since videos are silent anyway
        player?.volume = 0.0

        playerLayer = AVPlayerLayer(player: player)

        guard let playerLayer = playerLayer else { return }

        playerLayer.videoGravity = videoGravity
        self.layer?.addSublayer(playerLayer)

        // Set up looping or one-shot completion
        loopingObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            if loops {
                self?.player?.seek(to: .zero)
                self?.player?.play()
            } else {
                // Video completed, call the completion handler
                onCompletion?()
            }
        }
        
        if autoPlay {
            // Auto-play with a delay to ensure setup is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.player?.play()
            }
        }
    }
    
    /// Manually start or resume playback
    func play() {
        player?.play()
    }
    
    /// Pause playback
    func pause() {
        player?.pause()
    }
    
    /// Check if video is currently playing
    var isPlaying: Bool {
        guard let player = player else { return false }
        return player.rate > 0
    }
    
    override func layout() {
        super.layout()
        playerLayer?.frame = self.bounds
    }
    
    deinit {
        if let observer = loopingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player?.pause()
    }
}

}

// MARK: - Convenience Extensions

extension LoopingVideoPlayer {
    /// Creates a video player that fills the entire frame, cropping if necessary
    static func aspectFill(videoName: String, videoExtension: String = "mp4") -> LoopingVideoPlayer {
        LoopingVideoPlayer(
            videoName: videoName,
            videoExtension: videoExtension,
            videoGravity: .resizeAspectFill
        )
    }
    
    /// Creates a video player that fits the entire video within the frame, adding letterboxing if necessary
    static func aspectFit(videoName: String, videoExtension: String = "mp4") -> LoopingVideoPlayer {
        LoopingVideoPlayer(
            videoName: videoName,
            videoExtension: videoExtension,
            videoGravity: .resizeAspect
        )
    }
    
    /// Creates a video player that stretches the video to fill the frame exactly
    static func resize(videoName: String, videoExtension: String = "mp4") -> LoopingVideoPlayer {
        LoopingVideoPlayer(
            videoName: videoName,
            videoExtension: videoExtension,
            videoGravity: .resize
        )
    }
}