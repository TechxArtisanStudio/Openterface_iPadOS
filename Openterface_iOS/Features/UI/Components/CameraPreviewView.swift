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
                self.updatePreviewLayerTransform(previewLayer, in: uiView)
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
                previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
                
                // Apply frame and transform
                self.updatePreviewLayerTransform(previewLayer, in: view)
                
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
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        // Tap gesture for mouse clicks
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tapGesture)
        
        // Double-tap gesture for zoom reset
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapGesture)
        
        // Make single tap wait for double tap to fail
        tapGesture.require(toFail: doubleTapGesture)
        
        // Two-finger tap gesture for scrolling
        let twoFingerTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTapsRequired = 1
        twoFingerTapGesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTapGesture)
        
        // Long press for right click (fallback)
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
        
        // Pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchGesture.delegate = context.coordinator
        view.addGestureRecognizer(pinchGesture)
        
        // Three-finger pan gesture for viewport movement when zoomed
        let threeFingerPanGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleThreeFingerPan(_:)))
        threeFingerPanGesture.minimumNumberOfTouches = 3
        threeFingerPanGesture.maximumNumberOfTouches = 3
        threeFingerPanGesture.delegate = context.coordinator
        view.addGestureRecognizer(threeFingerPanGesture)
        
        // Store gesture references in coordinator for delegation
        context.coordinator.panGesture = panGesture
        context.coordinator.pinchGesture = pinchGesture
        context.coordinator.threeFingerPanGesture = threeFingerPanGesture
    }
    
    private func updatePreviewOrientation(in view: UIView, context: Context) {
        guard let previewLayer = context.coordinator.previewLayer else { return }
        
        DispatchQueue.main.async {
            self.updatePreviewLayerTransform(previewLayer, in: view)
            self.updateLayerOrientation(previewLayer)
        }
    }
    
    internal func updatePreviewLayerTransform(_ previewLayer: AVCaptureVideoPreviewLayer, in view: UIView) {
        let viewBounds = view.bounds
        let zoomFactor = cameraManager.currentZoomFactor
        let viewportPosition = cameraManager.viewportPosition
        
        // Always set the base frame to view bounds first
        previewLayer.frame = viewBounds
        
        if zoomFactor > 1.0 {
            // Use transform for zoom and pan - much more reliable than frame manipulation
            var transform = CATransform3DIdentity
            
            // Apply scale for zoom
            transform = CATransform3DScale(transform, zoomFactor, zoomFactor, 1.0)
            
            // Apply translation for panning (scaled appropriately)
            let scaledTranslationX = viewportPosition.x
            let scaledTranslationY = viewportPosition.y
            transform = CATransform3DTranslate(transform, scaledTranslationX, scaledTranslationY, 0.0)
            
            previewLayer.transform = transform
            
            print("🔍 Preview layer transform applied - zoom: \(zoomFactor), translation: (\(scaledTranslationX), \(scaledTranslationY))")
        } else {
            // Reset transform when not zoomed
            previewLayer.transform = CATransform3DIdentity
            print("🔍 Preview layer transform reset to identity")
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
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraPreviewView
        var previewLayer: AVCaptureVideoPreviewLayer?
        var backgroundImageView: UIImageView?
        private var orientationObserver: (() -> Void)?
        
        // Gesture references for delegation
        var panGesture: UIPanGestureRecognizer?
        var pinchGesture: UIPinchGestureRecognizer?
        var threeFingerPanGesture: UIPanGestureRecognizer?
        
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
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            print("🔍 Double tap gesture detected - resetting zoom")
            parent.cameraManager.resetZoom()
            
            // Immediately update the preview layer transform
            if let previewLayer = self.previewLayer, let view = gesture.view {
                DispatchQueue.main.async {
                    self.parent.updatePreviewLayerTransform(previewLayer, in: view)
                }
            }
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
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            print("🔍 Pinch gesture detected - scale: \(gesture.scale), state: \(gesture.state.rawValue)")
            
            switch gesture.state {
            case .began:
                print("🔍 Pinch gesture began with scale: \(gesture.scale)")
                print("🔍 Current zoom factor at start: \(parent.cameraManager.currentZoomFactor)")
                
            case .changed:
                // Calculate new zoom factor based on current zoom and pinch scale
                let currentZoom = parent.cameraManager.currentZoomFactor
                let newZoomFactor = currentZoom * gesture.scale
                
                print("🔍 Pinch calculation - current: \(currentZoom), scale: \(gesture.scale), new: \(newZoomFactor)")
                
                // Apply zoom through camera manager
                parent.cameraManager.setZoomFactor(newZoomFactor)
                
                // Immediately update the preview layer transform
                if let previewLayer = self.previewLayer, let view = gesture.view {
                    DispatchQueue.main.async {
                        self.parent.updatePreviewLayerTransform(previewLayer, in: view)
                    }
                }
                
                // Reset gesture scale to prevent compounding
                gesture.scale = 1.0
                
                print("🔍 Pinch changed - applied zoom factor: \(newZoomFactor), current published: \(parent.cameraManager.currentZoomFactor)")
                
            case .ended, .cancelled:
                print("🔍 Pinch gesture ended - final zoom: \(parent.cameraManager.currentZoomFactor)")
                
            default:
                break
            }
        }
        
        @objc func handleThreeFingerPan(_ gesture: UIPanGestureRecognizer) {
            print("🔍 Three-finger pan gesture detected - state: \(gesture.state.rawValue)")
            
            // Only allow panning when zoomed in
            guard parent.cameraManager.currentZoomFactor > 1.0 else {
                print("🔍 Three-finger pan ignored - not zoomed in")
                return
            }
            
            switch gesture.state {
            case .began:
                print("🔍 Three-finger pan began")
                
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                
                // Invert translation for more natural panning (pan right to see content on the left)
                let invertedTranslation = CGPoint(x: -translation.x, y: -translation.y)
                
                // Update viewport position through camera manager
                if let viewBounds = gesture.view?.bounds {
                    parent.cameraManager.updateViewportPosition(invertedTranslation, viewBounds: viewBounds)
                    
                    // Immediately update the preview layer transform
                    if let previewLayer = self.previewLayer {
                        DispatchQueue.main.async {
                            self.parent.updatePreviewLayerTransform(previewLayer, in: gesture.view!)
                        }
                    }
                }
                
                // Reset translation to get incremental changes
                gesture.setTranslation(.zero, in: gesture.view)
                
                print("🔍 Three-finger pan translation: \(translation), inverted: \(invertedTranslation)")
                
            case .ended, .cancelled:
                print("🔍 Three-finger pan ended")
                
            default:
                break
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        // MARK: - UIGestureRecognizerDelegate
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow pinch and pan to work simultaneously when pinch has 2 fingers
            if gestureRecognizer == pinchGesture && otherGestureRecognizer == panGesture {
                return true
            }
            if gestureRecognizer == panGesture && otherGestureRecognizer == pinchGesture {
                return true
            }
            
            // Allow three-finger pan to work independently
            if gestureRecognizer == threeFingerPanGesture || otherGestureRecognizer == threeFingerPanGesture {
                return false // Three-finger pan should be exclusive
            }
            
            return false
        }
    }
}

#Preview {
    CameraPreviewView(
        cameraManager: CameraSessionManager(),
        mouseManager: MouseInputManager(connectionManager: BluetoothConnectionManager())
    )
}
