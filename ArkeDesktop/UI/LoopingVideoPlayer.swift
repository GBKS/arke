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
    /// How the video is anchored when the scaled video overflows the view
    /// bounds (only takes effect with `.resizeAspectFill`)
    enum VideoAlignment {
        /// Overflow is cropped evenly on opposite edges
        case center
        /// The top edge stays pinned; overflow is cropped at the bottom
        case top
    }

    let videoName: String
    let videoExtension: String
    let videoGravity: AVLayerVideoGravity
    let videoAlignment: VideoAlignment
    let autoPlay: Bool
    let showErrorIndicator: Bool
    let loops: Bool
    let onCompletion: (() -> Void)?

    /// Creates a looping video player
    /// - Parameters:
    ///   - videoName: Name of the video file in the app bundle
    ///   - videoExtension: File extension (e.g., "mp4", "mov")
    ///   - videoGravity: How the video should be scaled within the view bounds
    ///   - videoAlignment: Where the video is anchored when aspect-fill cropping occurs
    ///   - autoPlay: Whether to start playing automatically
    ///   - showErrorIndicator: Whether to show a red background if video fails to load
    ///   - loops: Whether the video should loop continuously (default: true)
    ///   - onCompletion: Optional callback when video completes (only called if loops is false)
    init(
        videoName: String,
        videoExtension: String,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        videoAlignment: VideoAlignment = .center,
        autoPlay: Bool = true,
        showErrorIndicator: Bool = true,
        loops: Bool = true,
        onCompletion: (() -> Void)? = nil
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.videoGravity = videoGravity
        self.videoAlignment = videoAlignment
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
            videoAlignment: videoAlignment,
            autoPlay: autoPlay,
            showErrorIndicator: showErrorIndicator,
            loops: loops,
            onCompletion: onCompletion
        )
        return playerView
    }
    
    func updateNSView(_ nsView: PlayerView, context: Context) {
        // Swap the video if SwiftUI reuses this view with a different video name
        nsView.updateVideo(
            name: videoName,
            extension: videoExtension,
            videoGravity: videoGravity,
            videoAlignment: videoAlignment,
            autoPlay: autoPlay,
            showErrorIndicator: showErrorIndicator,
            loops: loops,
            onCompletion: onCompletion
        )
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
    private var currentVideoName: String?
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var pendingSwapCleanup: (() -> Void)?
    private var videoAlignment: LoopingVideoPlayer.VideoAlignment = .center
    private var videoSize: CGSize = .zero
    private var presentationSizeObservation: NSKeyValueObservation?

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
        videoAlignment: LoopingVideoPlayer.VideoAlignment,
        autoPlay: Bool,
        showErrorIndicator: Bool,
        loops: Bool,
        onCompletion: (() -> Void)?
    ) {
        currentVideoName = name
        self.videoAlignment = videoAlignment
        videoSize = .zero
        presentationSizeObservation?.invalidate()
        presentationSizeObservation = nil

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
        playerLayer.frame = self.bounds
        self.layer?.addSublayer(playerLayer)

        if videoAlignment == .top {
            // The overflowing layer hangs past the bottom edge; clip it
            self.layer?.masksToBounds = true
            observePresentationSize(of: player?.currentItem)
        }

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
    
    /// AVPlayerLayer always centers its aspect-fill crop, so top alignment
    /// sizes the layer to the fill dimensions manually (via `.resize`
    /// gravity) and pins its top edge, letting the view clip the bottom.
    /// The video's dimensions are only known once the item loads them.
    private func observePresentationSize(of item: AVPlayerItem?) {
        presentationSizeObservation = item?.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            let size = item.presentationSize
            guard size != .zero else { return }
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item else { return }
                self.videoSize = size
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.playerLayer?.videoGravity = .resize
                self.playerLayer?.frame = self.playerLayerFrame()
                CATransaction.commit()
            }
        }
    }

    private func playerLayerFrame() -> CGRect {
        guard videoAlignment == .top, videoSize != .zero,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = max(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let scaled = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        // Layer coordinates are bottom-left origin here, so pinning the top
        // edge means offsetting the origin down by the overflow amount
        return CGRect(
            x: (bounds.width - scaled.width) / 2,
            y: bounds.height - scaled.height,
            width: scaled.width,
            height: scaled.height
        )
    }

    /// Replaces the current video if the name changed, tearing down the old player first
    func updateVideo(
        name: String,
        extension ext: String,
        videoGravity: AVLayerVideoGravity,
        videoAlignment: LoopingVideoPlayer.VideoAlignment,
        autoPlay: Bool,
        showErrorIndicator: Bool,
        loops: Bool,
        onCompletion: (() -> Void)?
    ) {
        guard name != currentVideoName else { return }

        // Finish any in-flight swap so its outgoing layer doesn't linger
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        pendingSwapCleanup?()
        pendingSwapCleanup = nil

        // Keep the outgoing video on screen until the new one has a frame
        // ready, otherwise the view background flashes through the gap
        let oldPlayer = player
        let oldLayer = playerLayer
        let oldObserver = loopingObserver
        loopingObserver = nil
        self.layer?.backgroundColor = nil

        setupVideo(
            name: name,
            extension: ext,
            videoGravity: videoGravity,
            videoAlignment: videoAlignment,
            autoPlay: autoPlay,
            showErrorIndicator: showErrorIndicator,
            loops: loops,
            onCompletion: onCompletion
        )

        let cleanup = {
            oldPlayer?.pause()
            oldLayer?.removeFromSuperlayer()
            if let oldObserver {
                NotificationCenter.default.removeObserver(oldObserver)
            }
        }

        guard let newLayer = playerLayer else {
            // New video failed to load; drop the old one so the error state shows
            cleanup()
            return
        }

        pendingSwapCleanup = cleanup
        readyForDisplayObservation = newLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingSwapCleanup?()
                self.pendingSwapCleanup = nil
                self.readyForDisplayObservation?.invalidate()
                self.readyForDisplayObservation = nil
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
        playerLayer?.frame = playerLayerFrame()
    }

    deinit {
        if let observer = loopingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        presentationSizeObservation?.invalidate()
        player?.pause()
    }
}

}

// MARK: - Convenience Extensions

extension LoopingVideoPlayer {
    /// Creates a video player that fills the entire frame, cropping if necessary
    static func aspectFill(videoName: String, videoExtension: String = "mp4", alignment: VideoAlignment = .center) -> LoopingVideoPlayer {
        LoopingVideoPlayer(
            videoName: videoName,
            videoExtension: videoExtension,
            videoGravity: .resizeAspectFill,
            videoAlignment: alignment
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