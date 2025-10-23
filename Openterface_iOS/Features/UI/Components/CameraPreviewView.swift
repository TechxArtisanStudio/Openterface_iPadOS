//
//  CameraPreviewView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI
import AVFoundation
import CoreMedia
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var mouseManager: MouseInputManager
    @ObservedObject var appCoordinator: AppCoordinator
    
    func makeUIView(context: Context) -> UIView {
        // Use TouchEnabledView to capture coalesced touches from Apple Pencil
        let view = TouchEnabledView(frame: CGRect.zero)
        view.backgroundColor = UIColor.black
        view.clipsToBounds = true  // Ensure sublayers don't extend beyond bounds
        view.coordinator = context.coordinator  // Link coordinator for touch handling
        
        setupPreviewLayer(in: view, context: context)
        setupGestureRecognizers(for: view, context: context)
        setupDraggingIndicator(for: view, context: context)
        
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
        
        #if targetEnvironment(simulator)
        // On simulator, always try to setup the mock camera
        if TARGET_OS_SIMULATOR != 0 {
            setupPreviewLayer(in: uiView, context: context)
        }
        #endif
        
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
        
        // Update the simulator layer frame to match the view bounds
        #if targetEnvironment(simulator)
        if let simulatorLayer = context.coordinator.simulatorLayer {
            DispatchQueue.main.async {
                simulatorLayer.frame = uiView.bounds
            }
        }
        #endif
        
        // Update the background image view frame to match the view bounds
        if let imageView = context.coordinator.backgroundImageView {
            DispatchQueue.main.async {
                imageView.frame = uiView.bounds
            }
        }
        
        // Update preview orientation in case correction mode changed
        self.updatePreviewOrientation(in: uiView, context: context)
        
        // Update dragging indicator visibility
        if let label = context.coordinator.draggingIndicatorLabel {
            DispatchQueue.main.async {
                label.isHidden = !self.mouseManager.isSelectMode
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
            #if targetEnvironment(simulator)
            // Check if running on simulator - use mock camera
            if TARGET_OS_SIMULATOR != 0 {
                print("📱 [CameraPreview] Running on simulator - attempting to use mock camera")
                
                // Remove existing layers
                if let existingLayer = context.coordinator.simulatorLayer {
                    existingLayer.removeFromSuperlayer()
                    context.coordinator.simulatorLayer = nil
                }
                if let existingLayer = context.coordinator.previewLayer {
                    existingLayer.removeFromSuperlayer()
                    context.coordinator.previewLayer = nil
                }
                
                // Get simulator preview layer
                if let simulatorLayer = self.cameraManager.getSimulatorPreviewLayer() {
                    print("✅ [CameraPreview] Got simulator preview layer")
                    simulatorLayer.frame = view.bounds
                    view.layer.addSublayer(simulatorLayer)
                    context.coordinator.simulatorLayer = simulatorLayer
                    
                    // Force layout update
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                    return
                } else {
                    print("❌ [CameraPreview] Failed to get simulator preview layer")
                }
            }
            #endif
            
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
        
        Logger.shared.info("Guide image displayed - no Openterface camera connected", category: .ui)
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
        
        // Double-tap gesture for mouse click
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapGesture)
        
        // Triple-tap gesture for double click
        let tripleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTripleTap(_:)))
        tripleTapGesture.numberOfTapsRequired = 3
        tripleTapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tripleTapGesture)
        
        // Make single tap wait for double tap to fail, double tap wait for triple tap to fail
        tapGesture.require(toFail: doubleTapGesture)
        doubleTapGesture.require(toFail: tripleTapGesture)
        
        // Two-finger tap gesture for scrolling
        let twoFingerTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTapsRequired = 1
        twoFingerTapGesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTapGesture)
        
        // Long press for quick menu (right click or drag)
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
    
    private func setupDraggingIndicator(for view: UIView, context: Context) {
        let label = UILabel()
        label.text = "Dragging Mode Active"
        label.textColor = UIColor.white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true // Initially hidden
        
        view.addSubview(label)
        
        // Center the label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 200),
            label.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Store reference
        context.coordinator.draggingIndicatorLabel = label
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
        
        if zoomFactor > 1.0 {
            // Set frame to accommodate the entire zoomed content
            let zoomedSize = CGSize(width: viewBounds.width * zoomFactor, height: viewBounds.height * zoomFactor)
            previewLayer.frame = CGRect(origin: .zero, size: zoomedSize)
            
            // Position the layer so the desired viewport is visible in the view
            // Positive viewport position means we want to see content on the left,
            // so move the layer right to reveal it
            let offsetX = viewportPosition.x
            let offsetY = viewportPosition.y
            let centerX = viewBounds.midX + offsetX
            let centerY = viewBounds.midY + offsetY
            previewLayer.position = CGPoint(x: centerX, y: centerY)
            
            Logger.shared.debug("Preview layer frame/position applied - zoom: \(zoomFactor), viewport: (\(viewportPosition.x), \(viewportPosition.y)), frame: \(zoomedSize), position: (\(centerX), \(centerY))", category: .ui)
        } else {
            // Reset to normal size and center when not zoomed
            previewLayer.frame = viewBounds
            previewLayer.position = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
            // Logger.shared.debug("Preview layer reset to normal size", category: .ui)
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
            
//        case .rotated180:
//            // 180° rotation
//            switch interfaceOrientation {
//            case .portrait: return .portraitUpsideDown
//            case .portraitUpsideDown: return .portrait
//            case .landscapeLeft: return .landscapeRight
//            case .landscapeRight: return .landscapeLeft
//            default: return .portraitUpsideDown
//            }
//            
//        case .mirroredInverted:
//            // For now, same as inverted (mirroring handled separately)
//            switch interfaceOrientation {
//            case .portrait: return .portraitUpsideDown
//            case .portraitUpsideDown: return .portrait
//            case .landscapeLeft: return .landscapeRight
//            case .landscapeRight: return .landscapeLeft
//            default: return .portraitUpsideDown
//            }
        }
    }
}

// MARK: - Coordinator
extension CameraPreviewView {
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraPreviewView
        var previewLayer: AVCaptureVideoPreviewLayer?
        var simulatorLayer: CALayer?  // For simulator mock camera
        var backgroundImageView: UIImageView?
        private var orientationObserver: (() -> Void)?
        
        // Gesture references for delegation
        var panGesture: UIPanGestureRecognizer?
        var pinchGesture: UIPinchGestureRecognizer?
        var threeFingerPanGesture: UIPanGestureRecognizer?
        var draggingIndicatorLabel: UILabel?
        
        // Track pan gesture start position (internal access for TouchEnabledView)
        var panStartPosition: CGPoint = .zero
        
        // Track initial touch position from touchesBegan (for Apple Pencil)
        var initialTouchPosition: CGPoint? = nil
        
        // Touch tracking for drag end detection (internal access for TouchEnabledView)
        var isDragging: Bool = false
        var lastTouchLocation: CGPoint = .zero
        private var dragEndCheckTimer: Timer?
        
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
        
        // Helper to get gesture state name for debugging
        private func gestureStateName(_ state: UIGestureRecognizer.State) -> String {
            switch state {
            case .possible: return "possible"
            case .began: return "began"
            case .changed: return "changed"
            case .ended: return "ended"
            case .cancelled: return "cancelled"
            case .failed: return "failed"
            @unknown default: return "unknown"
            }
        }
        
        // Helper to calculate the video content rect within the view
        private func calculateVideoRect(in view: UIView) -> CGRect {
            let viewBounds = view.bounds
            
            // Try to get actual video dimensions from the preview layer
            var videoSize = CGSize(width: 16, height: 9) // Default 16:9
            if let previewLayer = self.previewLayer,
               let connection = previewLayer.connection,
               let inputPort = connection.inputPorts.first,
               let formatDescription = inputPort.formatDescription {
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                videoSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                Logger.shared.debug("Got video dimensions from format: \(dimensions.width)x\(dimensions.height)", category: .ui)
            } else {
                Logger.shared.debug("Using default 16:9 aspect ratio for video rect", category: .ui)
            }
            
            return AVMakeRect(aspectRatio: videoSize, insideRect: viewBounds)
        }
        
        // Start monitoring for drag end using polling
        private func startDragEndMonitoring() {
            Logger.shared.debug("Starting drag end monitoring timer", category: .ui)
            isDragging = true
            
            // Cancel any existing timer
            dragEndCheckTimer?.invalidate()
            
            // Create a timer that checks every 0.1 seconds if dragging has ended
            dragEndCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Check if pan gesture is no longer active
                if let panGesture = self.panGesture,
                   panGesture.state != .began && panGesture.state != .changed {
                    Logger.shared.debug("Drag end detected by polling - gesture state: \(self.gestureStateName(panGesture.state))", category: .ui)
                    self.endDragByPolling()
                }
            }
        }
        
        // End drag detected by polling
        private func endDragByPolling() {
            guard isDragging else { return }
            
            Logger.shared.debug("Ending drag via polling mechanism", category: .ui)
            isDragging = false
            
            // Stop timer
            dragEndCheckTimer?.invalidate()
            dragEndCheckTimer = nil
            
            // Trigger drag end
            self.parent.mouseManager.handleDragGesture(
                start: self.panStartPosition,
                current: self.lastTouchLocation,
                end: self.lastTouchLocation
            )
            Logger.shared.debug("Drag end triggered via polling - handleDragGesture called", category: .ui)
            
            panStartPosition = .zero
        }
        
        // Stop drag monitoring
        private func stopDragEndMonitoring() {
            Logger.shared.debug("Stopping drag end monitoring timer", category: .ui)
            isDragging = false
            dragEndCheckTimer?.invalidate()
            dragEndCheckTimer = nil
        }
        
        // MARK: - Gesture Handlers
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let currentLocation = gesture.location(in: gesture.view)
            let numberOfTouches = gesture.numberOfTouches
            
            let isZoomMode = parent.appCoordinator.isZoomMode
            Logger.shared.debug("Pan gesture - state: \(gesture.state.rawValue) [\(self.gestureStateName(gesture.state))], touches: \(numberOfTouches), location: \(currentLocation), zoomMode: \(isZoomMode)", category: .ui)
            
            // Check if this is a two-finger drag (scrolling or panning)
            if numberOfTouches == 2 {
                Logger.shared.debug("Two-finger pan detected - routing to two finger handler", category: .ui)
                handleTwoFingerPan(gesture)
                return
            }
            
            // Single finger pan in zoom mode - move viewport
            if isZoomMode && numberOfTouches == 1 {
                Logger.shared.debug("Single-finger pan in zoom mode - handling as viewport pan", category: .ui)
                
                // Only allow panning when zoomed in
                guard parent.cameraManager.currentZoomFactor > 1.0 else {
                    Logger.shared.debug("Single-finger pan ignored in zoom mode - not zoomed in", category: .ui)
                    return
                }
                
                switch gesture.state {
                case .began:
                    Logger.shared.debug("Single-finger viewport pan began in zoom mode", category: .ui)
                    
                case .changed:
                    let translation = gesture.translation(in: gesture.view)
                    
                    // Use translation directly for natural panning
                    // Drag right = viewport moves right (see content on right)
                    // Drag left = viewport moves left (see content on left)
                    
                    // Update viewport position through camera manager (synchronous)
                    if let view = gesture.view {
                        parent.cameraManager.updateViewportPosition(translation, viewBounds: view.bounds)
                        
                        // Immediately update the preview layer transform without animation
                        if let previewLayer = self.previewLayer {
                            CATransaction.begin()
                            CATransaction.setDisableActions(true) // Disable animations
                            self.parent.updatePreviewLayerTransform(previewLayer, in: view)
                            CATransaction.commit()
                        }
                    }
                    
                    // Reset translation to get incremental changes
                    gesture.setTranslation(.zero, in: gesture.view)
                    
                    Logger.shared.debug("Single-finger viewport pan - translation: \(translation)", category: .ui)
                    
                case .ended, .cancelled:
                    Logger.shared.debug("Single-finger viewport pan ended in zoom mode", category: .ui)
                    
                default:
                    break
                }
                return
            }
            
            // Handle single finger pan for mouse movement (only when not in zoom mode)
            // NOTE: When gesture ends, numberOfTouches becomes 0, so we need to check for that
            if numberOfTouches == 1 || (numberOfTouches == 0 && (gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed)) {
                switch gesture.state {
                case .began:
                    // Use initial touch position if available (for Apple Pencil), otherwise use current location
                    let startLocation = initialTouchPosition ?? currentLocation
                    Logger.shared.debug("Single-finger pan began at \(currentLocation), using start: \(startLocation)", category: .ui)
                    panStartPosition = startLocation
                    lastTouchLocation = currentLocation
                    
                    // Clear the initial touch position now that we've used it
                    initialTouchPosition = nil
                    
                    // Update view bounds for absolute mode coordinate normalization
                    if let view = gesture.view {
                        self.parent.mouseManager.updateViewBounds(view.bounds)
                        let videoRect = self.calculateVideoRect(in: view)
                        self.parent.mouseManager.updateVideoRect(videoRect)
                    }
                    
                    // NOTE: Don't call resetDragState() here!
                    // The previous gesture's handleDragEnded() already reset the state.
                    // Calling it again could interfere with the timing of the release packets.
                    
                    // Call handleDragGesture to initialize positions for new drag
                    self.parent.mouseManager.handleDragGesture(
                        start: startLocation,
                        current: currentLocation,
                        end: nil
                    )
                    
                    // Start polling-based drag end detection as fallback
                    self.startDragEndMonitoring()
                    
                case .changed:
                    Logger.shared.debug("Single-finger pan changed to location: \(currentLocation)", category: .ui)
                    lastTouchLocation = currentLocation
                    // Call handleDragGesture directly (not async) to maintain proper event ordering
                    self.parent.mouseManager.handleDragGesture(
                        start: self.panStartPosition,
                        current: currentLocation,
                        end: nil
                    )
                    
                case .ended, .cancelled:
                    Logger.shared.debug("Single-finger pan ended/cancelled at location: \(currentLocation), state: \(self.gestureStateName(gesture.state))", category: .ui)
                    
                    // Stop polling timer since we got the end event
                    self.stopDragEndMonitoring()
                    
                    // Call handleDragGesture directly (not async) to ensure end event is processed
                    self.parent.mouseManager.handleDragGesture(
                        start: self.panStartPosition,
                        current: currentLocation,
                        end: currentLocation
                    )
                    Logger.shared.debug("Single-finger pan - handleDragGesture called with end position", category: .ui)
                    panStartPosition = .zero
                
                case .failed:
                    Logger.shared.debug("Single-finger pan FAILED - cleaning up drag state", category: .ui)
                    
                    // Stop polling timer
                    self.stopDragEndMonitoring()
                    
                    // If gesture failed, we should still end the drag
                    self.parent.mouseManager.handleDragGesture(
                        start: self.panStartPosition,
                        current: currentLocation,
                        end: currentLocation
                    )
                    panStartPosition = .zero
                    
                default:
                    Logger.shared.debug("Single-finger pan - unhandled state: \(self.gestureStateName(gesture.state))", category: .ui)
                    break
                }
            }
        }
        
        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let currentLocation = gesture.location(in: gesture.view)
            let translation = gesture.translation(in: gesture.view)
            
            Logger.shared.debug("Two-finger pan - state: \(gesture.state.rawValue), location: \(currentLocation), translation: \(translation)", category: .ui)
            
            // In zoom mode, two-finger pan moves viewport (like three-finger pan in normal mode)
            if parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Two-finger pan in zoom mode - handling as viewport pan", category: .ui)
                
                // Only allow panning when zoomed in
                guard parent.cameraManager.currentZoomFactor > 1.0 else {
                    Logger.shared.debug("Two-finger pan ignored in zoom mode - not zoomed in", category: .ui)
                    return
                }
                
                switch gesture.state {
                case .began:
                    Logger.shared.debug("Two-finger viewport pan began in zoom mode", category: .ui)
                    
                case .changed:
                    // Use translation directly for natural panning
                    
                    // Update viewport position through camera manager
                    if let view = gesture.view {
                        parent.cameraManager.updateViewportPosition(translation, viewBounds: view.bounds)
                        
                        // Immediately update the preview layer transform without animation
                        if let previewLayer = self.previewLayer {
                            CATransaction.begin()
                            CATransaction.setDisableActions(true) // Disable animations
                            self.parent.updatePreviewLayerTransform(previewLayer, in: view)
                            CATransaction.commit()
                        }
                    }
                    
                    // Reset translation to get incremental changes
                    gesture.setTranslation(.zero, in: gesture.view)
                    
                    Logger.shared.debug("Two-finger viewport pan - translation: \(translation)", category: .ui)
                    
                case .ended, .cancelled:
                    Logger.shared.debug("Two-finger viewport pan ended in zoom mode", category: .ui)
                    
                default:
                    break
                }
                return
            }
            
            // Normal mode: two-finger pan is scrolling
            switch gesture.state {
            case .began:
                Logger.shared.debug("Two-finger scrolling started", category: .ui)
                parent.mouseManager.startTwoFingerScrolling()
                
            case .changed:
                Logger.shared.debug("Two-finger scrolling changed - translation: \(translation)", category: .ui)
                // Calculate scroll deltas from translation
                let deltaX = Int(translation.x)
                let deltaY = Int(translation.y)
                
                // Apply scrolling with sensitivity adjustment
                let scrollSensitivity = 10 // Adjust this for scroll speed
                let scrollDeltaX = deltaX / scrollSensitivity
                let scrollDeltaY = deltaY / scrollSensitivity // Remove inversion here - handleScroll will handle it
                
                if abs(scrollDeltaX) > 0 || abs(scrollDeltaY) > 0 {
                    Logger.shared.debug("Sending scroll - deltaX: \(scrollDeltaX), deltaY: \(scrollDeltaY)", category: .ui)
                    parent.mouseManager.handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY)
                }
                
                // Reset translation to get incremental changes
                gesture.setTranslation(.zero, in: gesture.view)
                
            case .ended, .cancelled:
                Logger.shared.debug("Two-finger scrolling ended", category: .ui)
                parent.mouseManager.endTwoFingerScrolling()
                
            default:
                break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            // In zoom mode, tap moves viewport to center on tapped location
            if parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Tap in zoom mode - moving viewport to center on: \(location)", category: .ui)
                
                // Only allow viewport movement when zoomed in
                guard parent.cameraManager.currentZoomFactor > 1.0,
                      let view = gesture.view else {
                    Logger.shared.debug("Tap ignored in zoom mode - not zoomed in or no view", category: .ui)
                    return
                }
                
                // Calculate the offset needed to center the tapped point
                let viewCenter = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2)
                let offset = CGPoint(x: location.x - viewCenter.x, y: location.y - viewCenter.y)
                
                // Use the offset directly: tap right to move viewport right
                // Update viewport position
                parent.cameraManager.updateViewportPosition(offset, viewBounds: view.bounds)
                
                // Immediately update the preview layer transform without animation
                if let previewLayer = self.previewLayer {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true) // Disable animations
                    self.parent.updatePreviewLayerTransform(previewLayer, in: view)
                    CATransaction.commit()
                }
                
                Logger.shared.debug("Viewport moved by offset: \(offset)", category: .ui)
                return
            }
            
            // Normal mode: tap is mouse click
            Logger.shared.debug("Single tap gesture detected in UI", category: .ui)
            Logger.shared.debug("Tap location: \(location)", category: .ui)
            parent.mouseManager.handleTap(at: location)
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            // Ignore double-tap in zoom mode
            if parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Double-tap ignored - zoom mode active", category: .ui)
                return
            }
            
            Logger.shared.debug("Double tap gesture detected", category: .ui)
            
            // If in drag mode, exit it; otherwise send click event
            if parent.mouseManager.isSelectMode {
                Logger.shared.debug("Exiting drag mode via double tap", category: .ui)
                parent.mouseManager.exitDraggingMode()
            } else {
                Logger.shared.debug("Sending click event via double tap", category: .ui)
                parent.mouseManager.handleClick()
            }
        }
        
        @objc func handleTripleTap(_ gesture: UITapGestureRecognizer) {
            // Ignore triple-tap in zoom mode
            if parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Triple-tap ignored - zoom mode active", category: .ui)
                return
            }
            
            Logger.shared.debug("Triple tap gesture detected - sending double click event", category: .ui)
            parent.mouseManager.handleDoubleClick()
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            // Ignore long press in zoom mode
            if parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Long press ignored - zoom mode active", category: .ui)
                return
            }
            
            if gesture.state == .began {
                Logger.shared.debug("Long press gesture detected in UI", category: .ui)
                let location = gesture.location(in: gesture.view)
                Logger.shared.debug("Long press location: \(location)", category: .ui)
                
                // Show quick menu at the press location
                showQuickMenu(at: location, in: gesture.view)
            }
        }
        
        private func showQuickMenu(at location: CGPoint, in view: UIView?) {
            guard let viewController = view?.window?.rootViewController else {
                Logger.shared.error("Could not find view controller to present menu", category: .ui)
                return
            }
            
            let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            
            // Right Click action
            let rightClickAction = UIAlertAction(title: "Right Click", style: .default) { [weak self] _ in
                guard let self = self else { return }
                Logger.shared.debug("Right Click selected from menu", category: .ui)
                self.parent.mouseManager.handleLongPress(at: location)
            }
            alertController.addAction(rightClickAction)
            
            // Drag action
            let dragAction = UIAlertAction(title: "Drag", style: .default) { [weak self] _ in
                guard let self = self else { return }
                Logger.shared.debug("Drag selected from menu", category: .ui)
                self.parent.mouseManager.enterDraggingMode()
            }
            alertController.addAction(dragAction)
            
            // Cancel action
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alertController.addAction(cancelAction)
            
            // Present the alert
            if let popoverController = alertController.popoverPresentationController {
                popoverController.sourceView = view
                popoverController.sourceRect = CGRect(origin: location, size: CGSize(width: 1, height: 1))
            }
            
            viewController.present(alertController, animated: true, completion: nil)
        }
        
        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            // Ignore two-finger tap in zoom mode (use it for zooming instead)
            if parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Two-finger tap ignored - zoom mode active, use pinch for zoom", category: .ui)
                return
            }
            
            Logger.shared.debug("handleTwoFingerTap gesture detected in UI", category: .ui)
            let location = gesture.location(in: gesture.view)
            Logger.shared.debug("Two-finger tap location: \(location)", category: .ui)
            // Two-finger tap should trigger scrolling, not right-click
            parent.mouseManager.handleLongPress(at: location)
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            Logger.shared.debug("Pinch gesture detected - scale: \(gesture.scale), state: \(gesture.state.rawValue)", category: .ui)
            
            // Only allow pinch zoom in zoom mode
            if !parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Pinch ignored - zoom mode not active", category: .ui)
                return
            }
            
            switch gesture.state {
            case .began:
                Logger.shared.debug("Pinch gesture began with scale: \(gesture.scale)", category: .ui)
                Logger.shared.debug("Current zoom factor at start: \(parent.cameraManager.currentZoomFactor)", category: .ui)
                
            case .changed:
                // Calculate new zoom factor based on current zoom and pinch scale
                let currentZoom = parent.cameraManager.currentZoomFactor
                let newZoomFactor = currentZoom * gesture.scale
                
                Logger.shared.debug("Pinch calculation - current: \(currentZoom), scale: \(gesture.scale), new: \(newZoomFactor)", category: .ui)
                
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
                
                Logger.shared.debug("Pinch changed - applied zoom factor: \(newZoomFactor), current published: \(parent.cameraManager.currentZoomFactor)", category: .ui)
                
            case .ended, .cancelled:
                Logger.shared.debug("Pinch gesture ended - final zoom: \(parent.cameraManager.currentZoomFactor)", category: .ui)
                
            default:
                break
            }
        }
        
        @objc func handleThreeFingerPan(_ gesture: UIPanGestureRecognizer) {
            Logger.shared.debug("Three-finger pan gesture detected - state: \(gesture.state.rawValue)", category: .ui)
            
            // Only allow three-finger panning in zoom mode
            if !parent.appCoordinator.isZoomMode {
                Logger.shared.debug("Three-finger pan ignored - zoom mode not active", category: .ui)
                return
            }
            
            // Only allow panning when zoomed in
            guard parent.cameraManager.currentZoomFactor > 1.0 else {
                Logger.shared.debug("Three-finger pan ignored - not zoomed in", category: .ui)
                return
            }
            
            switch gesture.state {
            case .began:
                Logger.shared.debug("Three-finger pan began", category: .ui)
                
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                
                // Use translation directly for natural panning
                
                // Update viewport position through camera manager
                if let view = gesture.view {
                    parent.cameraManager.updateViewportPosition(translation, viewBounds: view.bounds)
                    
                    // Immediately update the preview layer transform without animation
                    if let previewLayer = self.previewLayer {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true) // Disable animations
                        self.parent.updatePreviewLayerTransform(previewLayer, in: view)
                        CATransaction.commit()
                    }
                }
                
                // Reset translation to get incremental changes
                gesture.setTranslation(.zero, in: gesture.view)
                
                Logger.shared.debug("Three-finger pan translation: \(translation)", category: .ui)
                
            case .ended, .cancelled:
                Logger.shared.debug("Three-finger pan ended", category: .ui)
                
            default:
                break
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
            dragEndCheckTimer?.invalidate()
            dragEndCheckTimer = nil
        }
        
        // MARK: - UIGestureRecognizerDelegate
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow pinch and pan to work simultaneously
            if (gestureRecognizer == pinchGesture && otherGestureRecognizer == panGesture) ||
               (gestureRecognizer == panGesture && otherGestureRecognizer == pinchGesture) {
                return true
            }
            
            return false
        }
    }
}

// MARK: - Touch-Enabled View for Apple Pencil Support
/// Custom UIView that captures all touch events including coalesced touches from Apple Pencil
/// This ensures smooth drawing by processing all intermediate points that UIGestureRecognizer might miss
class TouchEnabledView: UIView {
    weak var coordinator: CameraPreviewView.Coordinator?
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Always call super first to allow gesture recognizers to work
        super.touchesBegan(touches, with: event)
        
        // Capture the initial touch position for Apple Pencil
        if let touch = touches.first,
           let coordinator = coordinator {
            let location = touch.location(in: self)
            
            // Store the initial touch position - this will be used when the pan gesture recognizes
            coordinator.initialTouchPosition = location
            
            Logger.shared.debug("[Apple Pencil] touchesBegan at \(location), pencil: \(touch.type == .pencil)", category: .ui)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Always call super first to allow gesture recognizers to work
        super.touchesMoved(touches, with: event)
        
        guard let touch = touches.first,
              let coordinator = coordinator,
              let event = event,
              coordinator.parent.mouseManager.isAbsoluteMode && !coordinator.parent.appCoordinator.isZoomMode else {
            return
        }
        
        // Check if this is an Apple Pencil touch - they generate coalesced touches
        let isPencil = touch.type == .pencil
        
        // Only process Apple Pencil touches - finger touches are handled by gesture recognizer alone
        guard isPencil else { return }
        
        // CRITICAL: Only process coalesced touches if we're actually in a drag
        // If panStartPosition is zero, the gesture hasn't begun yet - let it initialize first
        guard coordinator.panStartPosition != .zero else {
            Logger.shared.debug("[Apple Pencil] touchesMoved called before gesture began - skipping coalesced touch processing", category: .ui)
            return
        }
        
        // Get all coalesced touches - these are the intermediate points that happened between frames
        let coalescedTouches = event.coalescedTouches(for: touch) ?? [touch]
        
        Logger.shared.debug("[Apple Pencil] touchesMoved - coalesced touches: \(coalescedTouches.count)", category: .ui)
        
        // Process coalesced touches ONLY if there are multiple points (meaning we have intermediate data)
        // If there's only 1 touch, let the gesture recognizer handle it to avoid duplicate events
        if coalescedTouches.count > 1 {
            // Process all but the last coalesced touch (the last one will be handled by gesture recognizer)
            for coalescedTouch in coalescedTouches.dropLast() {
                let location = coalescedTouch.location(in: self)
                
                // Send each coalesced point directly to the mouse manager
                // This captures the intermediate points that gesture recognizer misses
                coordinator.parent.mouseManager.handleDragGesture(
                    start: coordinator.panStartPosition,
                    current: location,
                    end: nil
                )
                
                Logger.shared.debug("[Apple Pencil] Processing coalesced point: \(location)", category: .ui)
            }
            
            // Update last touch location for polling (use the last coalesced touch)
            if let lastTouch = coalescedTouches.last {
                coordinator.lastTouchLocation = lastTouch.location(in: self)
            }
        }
        // The last touch (or the only touch) will be handled by the gesture recognizer
        // This ensures we don't duplicate events and the gesture state machine works correctly
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Always call super first to allow gesture recognizers to work
        super.touchesEnded(touches, with: event)
        
        // Just log for debugging - gesture recognizer handles the actual end event
        if let touch = touches.first {
            let location = touch.location(in: self)
            Logger.shared.debug("[Apple Pencil] touchesEnded at \(location), pencil: \(touch.type == .pencil)", category: .ui)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Always call super first to allow gesture recognizers to work
        super.touchesCancelled(touches, with: event)
        
        // Just log for debugging
        if let touch = touches.first {
            let location = touch.location(in: self)
            Logger.shared.debug("[Apple Pencil] touchesCancelled at \(location)", category: .ui)
        }
    }
}

#Preview {
    CameraPreviewView(
        cameraManager: CameraSessionManager(),
        mouseManager: MouseInputManager(connectionManager: BluetoothConnectionManager()),
        appCoordinator: AppCoordinator()
    )
}
