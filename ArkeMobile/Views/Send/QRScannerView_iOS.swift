//
//  QRScannerView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/12/25.
//

import SwiftUI
import AVFoundation
import Combine
import os

nonisolated fileprivate let enableLogging = false
nonisolated fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "QRScannerView_iOS")

nonisolated fileprivate func log(_ level: OSLogType = .debug, _ message: String) {
    guard enableLogging else { return }
    logger.log(level: level, "\(message)")
}

/// QR Scanner view for scanning Bitcoin addresses and BIP-21 URIs
struct QRScannerView_iOS: View {
    let onCodeScanned: (String) -> Void
    let resetTrigger: Int
    
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: cameraManager.captureSession)
                .ignoresSafeArea()
            
            // Permission denied overlay
            if cameraManager.permissionDenied {
                permissionDeniedView
            }
            
            // Scanning reticle overlay
            if !cameraManager.permissionDenied {
                scanningOverlay
            }
        }
        .onAppear {
            log(.info, "View appeared - starting camera")
            cameraManager.checkPermissionsAndStartSession()
            cameraManager.onCodeDetected = onCodeScanned
        }
        .onDisappear {
            log(.info, "View disappeared - stopping camera")
            cameraManager.stopSession()
        }
        .onChange(of: resetTrigger) {
            log(.info, "Reset trigger changed - resetting scanner")
            cameraManager.resetScanner()
        }
    }
    
    @ViewBuilder
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 60))
                .foregroundStyle(.white)
            
            Text("error_camera_access_required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            
            Text("message_enable_camera")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    UIApplication.shared.open(settingsURL)
                } label: {
                    Text("button_open_settings")
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.9))
    }
    
    @ViewBuilder
    private var scanningOverlay: some View {
        VStack {
            Spacer()
            
            // Scanning frame
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white, lineWidth: 3)
                .frame(width: 250, height: 250)
            
            Spacer()
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame when view size changes
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Camera Manager

@MainActor
class CameraManager: NSObject, ObservableObject {
    @Published var permissionDenied = false
    
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    var onCodeDetected: ((String) -> Void)?
    
    private var hasScanned = false
    
    func checkPermissionsAndStartSession() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        log(.info, "Checking permissions - status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            log(.info, "Already authorized - starting session")
            // If session is already configured, just restart it
            if !captureSession.inputs.isEmpty && !captureSession.outputs.isEmpty {
                log(.info, "Session already configured - restarting")
                startSession()
            } else {
                log(.info, "Setting up session for first time")
                setupCaptureSession()
            }
        case .notDetermined:
            log(.info, "Permission not determined - requesting access")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    log(.info, "Permission response - granted: \(granted)")
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            log(.error, "Permission denied or restricted")
            permissionDenied = true
        @unknown default:
            log(.error, "Unknown permission status")
            permissionDenied = true
        }
    }
    
    private func setupCaptureSession() {
        log(.info, "Setting up capture session...")
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            log(.error, "No video capture device available")
            return
        }
        
        log(.info, "Video capture device found: \(videoCaptureDevice.localizedName)")
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            log(.info, "Video input created successfully")
        } catch {
            log(.error, "Error creating video input: \(error.localizedDescription)")
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            log(.info, "Video input added to session")
        } else {
            log(.error, "Cannot add video input to session")
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            log(.info, "Metadata output added to session")
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
            log(.info, "Metadata delegate set - listening for QR codes")
        } else {
            log(.error, "Cannot add metadata output to session")
            return
        }
        
        startSession()
    }
    
    func startSession() {
        log(.info, "Starting session - isRunning: \(self.captureSession.isRunning)")
        guard !captureSession.isRunning else {
            log(.info, "Session already running")
            return
        }
        
        Task.detached { [weak self] in
            self?.captureSession.startRunning()
            log(.info, "Session started - isRunning: \(self?.captureSession.isRunning ?? false)")
        }
    }
    
    func stopSession() {
        log(.info, "Stopping session - isRunning: \(self.captureSession.isRunning)")
        if captureSession.isRunning {
            Task.detached { [weak self] in
                self?.captureSession.stopRunning()
                log(.info, "Session stopped")
            }
        }
        hasScanned = false
        log(.debug, "hasScanned reset to false")
    }
    
    func resetScanner() {
        log(.info, "Resetting scanner - hasScanned: \(self.hasScanned) -> false")
        hasScanned = false
    }
}

// MARK: - Metadata Output Delegate

extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        log(.debug, "metadataOutput called - objects count: \(metadataObjects.count)")
        
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            log(.debug, "No valid QR code found in metadata")
            return
        }
        
        log(.info, "QR code detected: '\(stringValue)'")
        
        Task { @MainActor in
            log(.debug, "Processing on MainActor - hasScanned: \(hasScanned)")
            
            // Only process the first scan, ignore subsequent detections
            guard !hasScanned else {
                log(.debug, "Already scanned, ignoring")
                return
            }
            hasScanned = true
            log(.info, "First scan - setting hasScanned = true")
            
            // Provide haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            log(.debug, "Haptic feedback triggered")
            
            // Call the completion handler
            log(.info, "Calling onCodeDetected with: '\(stringValue)'")
            onCodeDetected?(stringValue)
        }
    }
}
