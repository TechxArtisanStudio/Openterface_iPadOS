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
        
        setupPreviewLayer(in: view, context: context)
        setupGestureRecognizers(for: view, context: context)
        
        // Setup orientation observer through coordinator
        context.coordinator.setupOrientationObserver { [weak view] in
            guard let view = view else { return }
            self.updatePreviewOrientation(in: view, context: context)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Setup preview layer when session becomes available
        if cameraManager.captureSession != nil && cameraManager.isAuthorized {
            setupPreviewLayer(in: uiView, context: context)
        } else if cameraManager.isAuthorized && !cameraManager.hasOpenterfaceCamera {
            // Show guide image when authorized but no Openterface camera
            setupPreviewLayer(in: uiView, context: context)
        }
        
        // Start session if it's not running and we have everything needed
        if cameraManager.isAuthorized && 
           cameraManager.selectedCamera != nil && 
           cameraManager.sessionState == .stopped {
            cameraManager.startSession()
        }
        
        // Update the preview layer frame to match the view bounds
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
        
        // Update the background image view frame to match the view bounds
        if let imageView = context.coordinator.backgroundImageView {
            DispatchQueue.main.async {
                imageView.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Setup Methods
    private func setupPreviewLayer(in view: UIView, context: Context) {
        // Ensure all UI operations happen on the main thread
        DispatchQueue.main.async {
            // Check if we already have a valid preview layer
            if let existingLayer = context.coordinator.previewLayer,
               existingLayer.session == self.cameraManager.captureSession,
               existingLayer.superlayer == view.layer {
                // Just update the frame
                existingLayer.frame = view.bounds
                return
            }
            
            // Remove existing preview layer if any
            if let existingLayer = context.coordinator.previewLayer {
                existingLayer.removeFromSuperlayer()
                context.coordinator.previewLayer = nil
            }
            
            // Remove existing background image view if any
            if let existingImageView = context.coordinator.backgroundImageView {
                existingImageView.removeFromSuperview()
                context.coordinator.backgroundImageView = nil
            }
            
            guard let previewLayer = self.cameraManager.getPreviewLayer() else {
                // Check if we have camera authorization but no Openterface camera
                if self.cameraManager.isAuthorized && !self.cameraManager.hasOpenterfaceCamera {
                    // Show the guide image instead of black background
                    self.setupGuideImageView(in: view, context: context)
                } else {
                    // Show a black background as fallback
                    view.backgroundColor = UIColor.black
                }
                return
            }
            
            // We have a preview layer - check if it's from an Openterface camera
            if self.cameraManager.hasOpenterfaceCamera {
                // Show the camera preview
                previewLayer.frame = view.bounds
                previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
                
                // Update orientation
                self.updateLayerOrientation(previewLayer)
                
                view.layer.addSublayer(previewLayer)
                context.coordinator.previewLayer = previewLayer
                
                // Force a layout update
                view.setNeedsLayout()
                view.layoutIfNeeded()
            } else {
                // Not an Openterface camera, show guide image
                self.setupGuideImageView(in: view, context: context)
            }
        }
    }
    
    private func setupGuideImageView(in view: UIView, context: Context) {
        // Create and configure the image view
        let imageView = UIImageView()
        imageView.image = UIImage(named: "guide")
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor.black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(imageView)
        
        // Set up constraints to fill the view
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store reference for cleanup
        context.coordinator.backgroundImageView = imageView
        
        print("✅ Guide image displayed - no Openterface camera connected")
    }
    
    private func setupGestureRecognizers(for view: UIView, context: Context) {
        // Clear existing gestures
        view.gestureRecognizers?.removeAll()
        
        // Pan gesture for mouse movement and two-finger scrolling
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2 // Allow both single and two-finger pans
        view.addGestureRecognizer(panGesture)
        
        // Tap gesture for mouse clicks
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tapGesture)
        
        // Two-finger tap gesture for scrolling
        let twoFingerTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTapsRequired = 1
        twoFingerTapGesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTapGesture)
        
        // Long press for right click (fallback)
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
    }
    
    private func updatePreviewOrientation(in view: UIView, context: Context) {
        guard let previewLayer = context.coordinator.previewLayer else { return }
        
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
            self.updateLayerOrientation(previewLayer)
        }
    }
    
    private func updateLayerOrientation(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { 
            return 
        }
        
        let interfaceOrientation = windowScene.interfaceOrientation
        
        guard let connection = previewLayer.connection else {
            return
        }
        
        // Configure mirroring first
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            // For external cameras (like capture cards), disable mirroring
            connection.isVideoMirrored = false
        }
        
        if connection.isVideoOrientationSupported {
            // For external cameras/capture cards, try corrected orientation
            let correctedOrientation = getCorrectedOrientation(for: interfaceOrientation)
            previewLayer.connection?.videoOrientation = correctedOrientation
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
        var backgroundImageView: UIImageView?
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
            let numberOfTouches = gesture.numberOfTouches
            
            print("🔍 Pan gesture - state: \(gesture.state.rawValue), touches: \(numberOfTouches), location: \(currentLocation)")
            
            // Check if this is a two-finger drag (scrolling)
            if numberOfTouches == 2 {
                print("🔍 Two-finger pan detected - routing to scroll")
                handleTwoFingerPan(gesture)
                return
            }
            
            // Single finger pan - regular mouse movement
            switch gesture.state {
            case .began:
                print("🔍 Single-finger pan began")
                parent.mouseManager.handleDragGesture(
                    start: currentLocation,
                    current: currentLocation,
                    end: nil
                )
                
            case .changed:
                print("🔍 Single-finger pan changed")
                // Move mouse handling to background queue to prevent UI blocking
                DispatchQueue.global(qos: .userInteractive).async {
                    self.parent.mouseManager.handleDragGesture(
                        start: .zero, // Not used during ongoing drag
                        current: currentLocation,
                        end: nil
                    )
                }
                
            case .ended, .cancelled:
                print("🔍 Single-finger pan ended/cancelled")
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
        
        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let currentLocation = gesture.location(in: gesture.view)
            let translation = gesture.translation(in: gesture.view)
            
            print("🔍 Two-finger pan - state: \(gesture.state.rawValue), location: \(currentLocation), translation: \(translation)")
            
            switch gesture.state {
            case .began:
                print("🔍 Two-finger scrolling started")
                parent.mouseManager.startTwoFingerScrolling()
                
            case .changed:
                print("🔍 Two-finger scrolling changed - translation: \(translation)")
                // Calculate scroll deltas from translation
                let deltaX = Int(translation.x)
                let deltaY = Int(translation.y)
                
                // Apply scrolling with sensitivity adjustment
                let scrollSensitivity = 5 // Adjust this for scroll speed
                let scrollDeltaX = deltaX / scrollSensitivity
                let scrollDeltaY = deltaY / scrollSensitivity // Remove inversion here - handleScroll will handle it
                
                if abs(scrollDeltaX) > 0 || abs(scrollDeltaY) > 0 {
                    print("🔍 Sending scroll - deltaX: \(scrollDeltaX), deltaY: \(scrollDeltaY)")
                    parent.mouseManager.handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY)
                }
                
                // Reset translation to get incremental changes
                gesture.setTranslation(.zero, in: gesture.view)
                
            case .ended, .cancelled:
                print("🔍 Two-finger scrolling ended")
                parent.mouseManager.endTwoFingerScrolling()
                
            default:
                break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            print("🔍 Single tap gesture detected in UI")
            let location = gesture.location(in: gesture.view)
            print("🔍 Tap location: \(location)")
            parent.mouseManager.handleTap(at: location)
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                print("🔍 Long press gesture detected in UI")
                let location = gesture.location(in: gesture.view)
                print("🔍 Long press location: \(location)")
                parent.mouseManager.handleLongPress(at: location)
            }
        }
        
        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            print("🔍 handleTwoFingerTap gesture detected in UI")
            let location = gesture.location(in: gesture.view)
            print("🔍 Two-finger tap location: \(location)")
            // Two-finger tap should trigger scrolling, not right-click
            parent.mouseManager.handleLongPress(at: location)
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
