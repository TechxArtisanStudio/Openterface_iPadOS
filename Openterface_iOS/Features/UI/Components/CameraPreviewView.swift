//
//  CameraPreviewView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var mouseManager: MouseInputManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        view.backgroundColor = UIColor.black
        view.clipsToBounds = true  // Ensure sublayers don't extend beyond bounds
        
        print("=== makeUIView called ===")
        print("Initial view frame: \(view.frame)")
        print("Initial view bounds: \(view.bounds)")
        print("Camera authorized: \(cameraManager.isAuthorized)")
        print("Camera session available: \(cameraManager.captureSession != nil)")
        print("Camera session state: \(cameraManager.sessionState)")
        
        setupPreviewLayer(in: view, context: context)
        setupGestureRecognizers(for: view, context: context)
        
        // Setup orientation observer through coordinator
        context.coordinator.setupOrientationObserver { [weak view] in
            guard let view = view else { return }
            print("=== Orientation change detected ===")
            self.updatePreviewOrientation(in: view, context: context)
        }
        
        print("✅ makeUIView completed, returning view")
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        print("=== updateUIView called ===")
        print("UIView frame: \(uiView.frame)")
        print("UIView bounds: \(uiView.bounds)")
        print("Camera session state: \(cameraManager.sessionState)")
        print("Camera session available: \(cameraManager.captureSession != nil)")
        print("Camera authorized: \(cameraManager.isAuthorized)")
        print("Selected camera: \(cameraManager.selectedCamera?.localizedName ?? "None")")
        print("Existing preview layer: \(context.coordinator.previewLayer != nil)")
        
        // Setup preview layer when session becomes available
        if cameraManager.captureSession != nil && cameraManager.isAuthorized {
            print("🎬 Conditions met for preview setup - calling setupPreviewLayer")
            setupPreviewLayer(in: uiView, context: context)
        } else {
            print("⚠️ Conditions NOT met for preview setup:")
            print("  - Session available: \(cameraManager.captureSession != nil)")
            print("  - Authorized: \(cameraManager.isAuthorized)")
        }
        
        // Start session if it's not running and we have everything needed
        if cameraManager.isAuthorized && 
           cameraManager.selectedCamera != nil && 
           cameraManager.sessionState == .stopped {
            print("🚀 Triggering session start from updateUIView")
            cameraManager.startSession()
        }
        
        // Update the preview layer frame to match the view bounds
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                let oldFrame = previewLayer.frame
                previewLayer.frame = uiView.bounds
                print("📐 Preview layer frame updated from \(oldFrame) to \(previewLayer.frame)")
            }
        } else {
            print("⚠️ No preview layer to update frame")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Setup Methods
    private func setupPreviewLayer(in view: UIView, context: Context) {
        // Ensure all UI operations happen on the main thread
        DispatchQueue.main.async {
            print("🎬 === setupPreviewLayer called ===")
            print("View frame: \(view.frame)")
            print("View bounds: \(view.bounds)")
            print("View has superview: \(view.superview != nil)")
            print("Camera manager session available: \(self.cameraManager.captureSession != nil)")
            
            // Check if we already have a valid preview layer
            if let existingLayer = context.coordinator.previewLayer,
               existingLayer.session == self.cameraManager.captureSession,
               existingLayer.superlayer == view.layer {
                print("✅ Preview layer already exists and is valid - skipping recreation")
                // Just update the frame
                existingLayer.frame = view.bounds
                return
            }
            
            // Remove existing preview layer if any
            if let existingLayer = context.coordinator.previewLayer {
                print("🗑️ Removing existing preview layer")
                existingLayer.removeFromSuperlayer()
                context.coordinator.previewLayer = nil
            }
            
            guard let previewLayer = self.cameraManager.getPreviewLayer() else {
                print("❌ No preview layer available from camera manager")
                // Show a black background as fallback
                view.backgroundColor = UIColor.black
                return
            }
            
            print("✅ Got preview layer from camera manager")
            print("Preview layer session: \(previewLayer.session != nil)")
            print("Preview layer session running: \(previewLayer.session?.isRunning ?? false)")
            
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            
            print("📐 Set preview layer frame to: \(previewLayer.frame)")
            print("📐 Set video gravity to: \(previewLayer.videoGravity)")
            
            // Update orientation
            self.updateLayerOrientation(previewLayer)
            
            print("🏗️ Adding preview layer to view")
            view.layer.addSublayer(previewLayer)
            context.coordinator.previewLayer = previewLayer
            
            print("✅ Preview layer setup completed")
            print("Preview layer frame: \(previewLayer.frame)")
            print("Preview layer session: \(previewLayer.session != nil)")
            print("View sublayers count: \(view.layer.sublayers?.count ?? 0)")
            
            // Force a layout update
            view.setNeedsLayout()
            view.layoutIfNeeded()
            print("🔄 Forced view layout update")
        }
    }
    
    private func setupGestureRecognizers(for view: UIView, context: Context) {
        // Clear existing gestures
        view.gestureRecognizers?.removeAll()
        
        // Pan gesture for mouse movement
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        // Tap gesture for mouse clicks
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tapGesture)
        
        // Two-finger tap gesture for right click
        let twoFingerTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTapsRequired = 1
        twoFingerTapGesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTapGesture)
        
        // Long press for right click (fallback)
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
        
        print("✅ Gesture recognizers setup completed")
    }
    
    private func updatePreviewOrientation(in view: UIView, context: Context) {
        guard let previewLayer = context.coordinator.previewLayer else { return }
        
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
            self.updateLayerOrientation(previewLayer)
            print("Preview layer orientation updated: \(previewLayer.frame)")
        }
    }
    
    private func updateLayerOrientation(_ previewLayer: AVCaptureVideoPreviewLayer) {
        print("🔄 === updateLayerOrientation called ===")
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { 
            print("❌ No window scene available")
            return 
        }
        
        let interfaceOrientation = windowScene.interfaceOrientation
        print("Current interface orientation: \(interfaceOrientation.rawValue)")
        
        guard let connection = previewLayer.connection else {
            print("❌ No connection available on preview layer")
            return
        }
        
        print("Connection isVideoOrientationSupported: \(connection.isVideoOrientationSupported)")
        print("Connection isVideoMirroringSupported: \(connection.isVideoMirroringSupported)")
        
        // Configure mirroring first
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            // For external cameras (like capture cards), disable mirroring
            connection.isVideoMirrored = false
            print("✅ Video mirroring disabled for external camera")
        }
        
        if connection.isVideoOrientationSupported {
            let oldOrientation = connection.videoOrientation
            
            // For external cameras/capture cards, try corrected orientation
            let correctedOrientation = getCorrectedOrientation(for: interfaceOrientation)
            previewLayer.connection?.videoOrientation = correctedOrientation
            
            print("Video orientation changed from \(oldOrientation.rawValue) to \(correctedOrientation.rawValue) (corrected for external camera)")
        } else {
            print("⚠️ Video orientation not supported on this connection")
        }
    }
    
    /// Get corrected orientation for external cameras that may have flipped video
    private func getCorrectedOrientation(for interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        // Use the camera manager's orientation correction mode if available
        switch cameraManager.orientationCorrectionMode {
        case .normal:
            // Standard orientation mapping
            switch interfaceOrientation {
            case .portrait: return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: return .portrait
            }
            
        case .inverted:
            // Inverted orientation mapping (fixes up/down and left/right flips)
            switch interfaceOrientation {
            case .portrait: return .portraitUpsideDown
            case .portraitUpsideDown: return .portrait
            case .landscapeLeft: return .landscapeRight
            case .landscapeRight: return .landscapeLeft
            default: return .portraitUpsideDown
            }
            
        case .rotated180:
            // 180° rotation
            switch interfaceOrientation {
            case .portrait: return .portraitUpsideDown
            case .portraitUpsideDown: return .portrait
            case .landscapeLeft: return .landscapeRight
            case .landscapeRight: return .landscapeLeft
            default: return .portraitUpsideDown
            }
            
        case .mirroredInverted:
            // For now, same as inverted (mirroring handled separately)
            switch interfaceOrientation {
            case .portrait: return .portraitUpsideDown
            case .portraitUpsideDown: return .portrait
            case .landscapeLeft: return .landscapeRight
            case .landscapeRight: return .landscapeLeft
            default: return .portraitUpsideDown
            }
        }
    }
}

// MARK: - Coordinator
extension CameraPreviewView {
    class Coordinator: NSObject {
        var parent: CameraPreviewView
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var orientationObserver: (() -> Void)?
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
            super.init()
        }
        
        func setupOrientationObserver(_ observer: @escaping () -> Void) {
            self.orientationObserver = observer
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(orientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }
        
        @objc private func orientationDidChange() {
            orientationObserver?()
        }
        
        // MARK: - Gesture Handlers
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let currentLocation = gesture.location(in: gesture.view)
            
            switch gesture.state {
            case .began:
                parent.mouseManager.handleDragGesture(
                    start: currentLocation,
                    current: currentLocation,
                    end: nil
                )
                
            case .changed:
                // Move mouse handling to background queue to prevent UI blocking
                DispatchQueue.global(qos: .userInteractive).async {
                    self.parent.mouseManager.handleDragGesture(
                        start: .zero, // Not used during ongoing drag
                        current: currentLocation,
                        end: nil
                    )
                }
                
            case .ended, .cancelled:
                DispatchQueue.global(qos: .userInteractive).async {
                    self.parent.mouseManager.handleDragGesture(
                        start: .zero,
                        current: currentLocation,
                        end: currentLocation
                    )
                }
                
            default:
                break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.mouseManager.handleTap(at: location)
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                let location = gesture.location(in: gesture.view)
                parent.mouseManager.handleLongPress(at: location)
            }
        }
        
        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            print("Two finger tap detected at: \(location)")
            parent.mouseManager.handleRightClick()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

#Preview {
    CameraPreviewView(
        cameraManager: CameraSessionManager(),
        mouseManager: MouseInputManager(connectionManager: BluetoothConnectionManager())
    )
}
