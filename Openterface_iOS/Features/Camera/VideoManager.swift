//
//  VideoManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import AVFoundation
import Combine
import UIKit

final class VideoManager: NSObject, ObservableObject, CameraManagementProtocol, DeviceDiscoveryProtocol {
    // MARK: - Published Properties
    @Published var isAuthorized = false {
        didSet {
            print("🔄 isAuthorized changed from \(oldValue) to \(isAuthorized)")
        }
    }
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var currentDeviceName: String?
    @Published var sessionId = UUID()
    @Published var sessionState: CameraSessionState = .stopped
    @Published var hasNewCameraDetected = false

    // Audio device detection (not used by VideoManager, but required by protocol)
    @Published var hasNewAudioDeviceDetected = false

    // Orientation correction for external cameras
    @Published var orientationCorrectionMode: OrientationCorrectionMode = .counterClockwise90

    // Zoom properties
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 5.0

    // Viewport position properties for panning when zoomed
    @Published var viewportPosition: CGPoint = CGPoint.zero
    @Published var maxViewportOffset: CGPoint = CGPoint.zero

    // Resolution property
    @Published var currentResolution: String = "1080p"

    // Audio properties (stub implementations for protocol conformance)
    var isAudioAuthorized: Bool { false }
    var currentAudioDeviceName: String? { nil }

    // MARK: - Private Properties
    private var _captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var deviceDiscoverySession: AVCaptureDevice.DiscoverySession?

    // Simulator detection and mock
    private var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    #if targetEnvironment(simulator)
    private var simulatorMock: SimulatorCameraMock?
    private var simulatorPreviewLayer: AVPlayerLayer?
    #endif

    // MARK: - Public Properties for UI
    var captureSession: AVCaptureSession? {
        return _captureSession
    }

    /// Check if an Openterface camera is currently connected and selected
    var hasOpenterfaceCamera: Bool {
        guard let selectedCamera = selectedCamera else { return false }

        // Check if the camera name contains "Openterface" (case insensitive)
        let cameraName = selectedCamera.localizedName.lowercased()
        let lower = cameraName
        let keywords = ["openterface", "usb2 video", "usb3 video"]
        return keywords.contains { lower.contains($0) }
    }

    /// Get or create a preview layer for the current capture session
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        print("🎬 === getPreviewLayer called ===")

        #if targetEnvironment(simulator)
        // On simulator, use mock camera with test video
        if isRunningOnSimulator {
            print("📱 Running on simulator - using mock camera")
            
            if simulatorPreviewLayer == nil {
                // Initialize simulator mock if needed
                if simulatorMock == nil {
                    simulatorMock = SimulatorCameraMock()
                }
                
                // Get preview layer from mock
                if let mockLayer = simulatorMock?.getPreviewLayer() {
                    simulatorPreviewLayer = mockLayer
                    print("✅ Created simulator mock preview layer")
                    
                    // Start mock camera if not already active
                    if simulatorMock?.isActive == false {
                        simulatorMock?.startMockCamera { sampleBuffer in
                            // Handle sample buffers if needed for recording etc.
                            // For now, just logging
                            print("📹 [Simulator] Received frame")
                        }
                    }
                }
            }
            
            // Return the mock layer cast as AVCaptureVideoPreviewLayer for compatibility
            // Note: This is a workaround since AVPlayerLayer and AVCaptureVideoPreviewLayer
            // are different types but both are CALayer subclasses
            if let mockLayer = simulatorPreviewLayer {
                // Create a wrapper that will work with the existing preview view
                let wrapperLayer = AVCaptureVideoPreviewLayer()
                wrapperLayer.videoGravity = .resizeAspectFill
                
                // We'll add the mock layer as a sublayer in the preview view
                // For now, return nil and handle this specially in the UI
                print("⚠️ Simulator mode: Preview will be handled specially")
                return nil
            }
        }
        #endif

        guard let captureSession = _captureSession else {
            print("❌ No capture session available for preview layer")
            print("Session state: \(sessionState)")
            print("Selected camera: \(selectedCamera?.localizedName ?? "None")")
            print("Is authorized: \(isAuthorized)")
            return nil
        }

        print("✅ Capture session available")
        print("  - Session inputs: \(captureSession.inputs.count)")
        print("  - Session outputs: \(captureSession.outputs.count)")
        print("  - Session running: \(captureSession.isRunning)")
        print("  - Session interrupted: \(captureSession.isInterrupted)")
        print("  - Session preset: \(captureSession.sessionPreset.rawValue)")

        // Log input details
        for (index, input) in captureSession.inputs.enumerated() {
            if let deviceInput = input as? AVCaptureDeviceInput {
                print("  - Input \(index): \(deviceInput.device.localizedName)")
            }
        }

        // Log output details
        for (index, output) in captureSession.outputs.enumerated() {
            print("  - Output \(index): \(type(of: output))")
        }

        // Create a new preview layer each time to avoid reuse issues
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspect

        print("🏗️ Created AVCaptureVideoPreviewLayer")
        print("  - Video gravity: \(previewLayer.videoGravity)")

        // Set initial orientation - let the preview view handle this
        if let connection = previewLayer.connection {
            print("✅ Preview layer connection available")
            print("  - Connection enabled: \(connection.isEnabled)")
            print("  - Connection active: \(connection.isActive)")
            print("  - Video orientation supported: \(connection.isVideoOrientationSupported)")
            print("  - Video mirroring supported: \(connection.isVideoMirroringSupported)")

            // Configure mirroring for external cameras
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                // Don't mirror external cameras (like capture cards)
                connection.isVideoMirrored = false
                print("✅ Video mirroring disabled for external camera")
            }

            // Don't set orientation here - let the preview view handle device-specific orientation
            print("✅ Preview layer connection configured (orientation will be set by preview view)")
        } else {
            print("❌ Preview layer connection not available")
        }

        print("✅ Created new preview layer successfully")
        return previewLayer
    }
    
    #if targetEnvironment(simulator)
    /// Get a simulator preview layer (AVPlayerLayer) for testing
    /// This is only available when running on simulator
    func getSimulatorPreviewLayer() -> CALayer? {
        print("🎬 === getSimulatorPreviewLayer called ===")
        
        guard isRunningOnSimulator else {
            print("❌ Not running on simulator")
            return nil
        }
        
        if simulatorPreviewLayer == nil {
            // Initialize simulator mock if needed
            if simulatorMock == nil {
                print("📱 Creating SimulatorCameraMock...")
                simulatorMock = SimulatorCameraMock()
            }
            
            // Start mock camera FIRST (this creates the player)
            if simulatorMock?.isActive == false {
                print("📹 Starting mock camera...")
                simulatorMock?.startMockCamera { sampleBuffer in
                    // Handle sample buffers if needed for recording etc.
                    // Could be passed to recording manager here
                }
            }
            
            // NOW get preview layer from mock (after player is created)
            if let mockLayer = simulatorMock?.getPreviewLayer() {
                simulatorPreviewLayer = mockLayer
                print("✅ Created simulator mock preview layer")
            } else {
                print("❌ Failed to create mock preview layer")
            }
        }
        
        return simulatorPreviewLayer
    }
    
    /// Check if simulator mode is active
    var isSimulatorModeActive: Bool {
        return isRunningOnSimulator && simulatorMock != nil
    }
    
    /// Capture a screenshot from simulator mock camera
    func captureSimulatorScreenshot() -> UIImage? {
        return simulatorMock?.captureCurrentFrame()
    }
    #endif

    override init() {
        super.init()
        print("🎬 VideoManager init - starting setup")
        
        #if targetEnvironment(simulator)
        if isRunningOnSimulator {
            print("📱 Running on iOS Simulator - mock camera will be available")
            // Mark as authorized for simulator (no actual camera permission needed)
            self.isAuthorized = true
            self.currentDeviceName = "Simulator Test Camera"
        }
        #endif
        
        checkCameraAuthorization()
        setupDeviceDiscovery()
        print("🎬 VideoManager init - completed, isAuthorized: \(isAuthorized)")
    }

    deinit {
        cleanup()
    }
}

// MARK: - CameraManagementProtocol Conformance
extension VideoManager {
    func checkCameraAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("🔍 checkCameraAuthorization - raw status: \(status)")
        print("🔍 checkCameraAuthorization - status description: \(status.rawValue)")
        print("🔍 checkCameraAuthorization - current isAuthorized: \(isAuthorized)")
        print("🔍 checkCameraAuthorization - running on simulator: \(isRunningOnSimulator)")

        // Check all possible values for debugging
        switch status {
        case .notDetermined:
            print("🔍 Status is .notDetermined")
        case .restricted:
            print("🔍 Status is .restricted")
        case .denied:
            print("🔍 Status is .denied")
        case .authorized:
            print("🔍 Status is .authorized")
        @unknown default:
            print("🔍 Status is unknown: \(status)")
        }

        let wasAuthorized = self.isAuthorized
        let shouldBeAuthorized: Bool

        // On simulator, respect the simulator-specific authorization we set during init
        if isRunningOnSimulator {
            // If we're on simulator and we've already set isAuthorized to true during init (for mock camera),
            // keep it true regardless of the actual authorization status
            shouldBeAuthorized = self.isAuthorized || (status == .authorized)
        } else {
            // On real device, use the actual authorization status
            shouldBeAuthorized = (status == .authorized)
        }

        // Update immediately if on main queue, otherwise dispatch to main queue
        if Thread.isMainThread {
            self.isAuthorized = shouldBeAuthorized
            print("🔍 checkCameraAuthorization - updated isAuthorized from \(wasAuthorized) to \(self.isAuthorized) (sync)")
        } else {
            DispatchQueue.main.sync {
                self.isAuthorized = shouldBeAuthorized
                print("🔍 checkCameraAuthorization - updated isAuthorized from \(wasAuthorized) to \(self.isAuthorized) (async)")
            }
        }

        if status == .authorized {
            print("✅ Camera is authorized, setting up camera...")
            setupCamera()
            // Auto-start session if we have authorization and a selected camera
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.selectedCamera != nil && self.sessionState == .stopped {
                    self.startSession()
                }
            }
        } else {
            print("❌ Camera not authorized - status: \(status)")
            if isRunningOnSimulator {
                print("📱 Note: Running on simulator - camera permissions may behave differently")
            }
        }
    }

    /// Force refresh authorization status - useful for debugging
    func forceRefreshAuthorization() {
        print("🔄 Force refreshing authorization status...")
        checkCameraAuthorization()
    }

    func requestCameraAccess() {
        print("🔍 requestCameraAccess called")
        AVCaptureDevice.requestAccess(for: .video) { granted in
            print("🔍 requestCameraAccess callback - granted: \(granted)")
            DispatchQueue.main.async {
                let wasAuthorized = self.isAuthorized
                self.isAuthorized = granted
                print("🔍 requestCameraAccess - updated isAuthorized from \(wasAuthorized) to \(self.isAuthorized)")

                if granted {
                    print("✅ Camera access granted, setting up camera...")
                    self.setupCamera()
                    // Auto-start session after permission is granted
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if self.selectedCamera != nil && self.sessionState == .stopped {
                            self.startSession()
                        }
                    }
                } else {
                    print("❌ Camera access denied by user")
                }
            }
        }
    }

    func switchCamera(to device: AVCaptureDevice) {
        guard let captureSession = _captureSession else {
            // No session exists yet, just update the selected camera
            selectedCamera = device
            currentDeviceName = device.localizedName
            return
        }

        print("🔄 Switching camera to: \(device.localizedName)")

        // Use beginConfiguration/commitConfiguration for smoother transition
        captureSession.beginConfiguration()

        // Remove existing video input
        if let currentInput = captureSession.inputs.first(where: { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.video)
        }) {
            captureSession.removeInput(currentInput)
            print("🔄 Removed current video input")
        }

        // Add new video input
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                print("✅ Added new video input: \(device.localizedName)")

                // Update state
                selectedCamera = device
                currentDeviceName = device.localizedName

                // Configure the new connection for stability
                captureSession.commitConfiguration()
                configureVideoConnection(for: captureSession)

                // Update zoom range for new camera
                updateZoomRange()

                // Update session ID to trigger UI refresh
                DispatchQueue.main.async {
                    self.sessionId = UUID()
                }

                print("✅ Camera switched successfully without stopping session")
            } else {
                print("❌ Cannot add new video input")
                captureSession.commitConfiguration()
            }
        } catch {
            print("❌ Failed to switch camera: \(error)")
            captureSession.commitConfiguration()
        }
    }

    // MARK: - Audio methods (stub implementations for protocol conformance)
    func checkAudioAuthorization() {
        // VideoManager doesn't handle audio
    }

    func requestAudioAccess() {
        // VideoManager doesn't handle audio
    }

    func startSession() {
        guard isAuthorized else {
            print("❌ Camera not authorized")
            return
        }

        guard sessionState != .running && sessionState != .starting else {
            print("📹 Camera session already running or starting")
            return
        }

        // Defer @Published update to avoid "Publishing changes from within view updates"
        DispatchQueue.main.async { [weak self] in
            self?.sessionState = .starting
        }
        
        #if targetEnvironment(simulator)
        // In simulator mode, we don't have a real capture session
        if isRunningOnSimulator {
            print("📱 [Simulator] Starting mock camera session...")
            
            // Ensure simulator mock is initialized and started
            if simulatorMock == nil {
                simulatorMock = SimulatorCameraMock()
            }
            
            if simulatorMock?.isActive == false {
                simulatorMock?.startMockCamera { sampleBuffer in
                    // Handle sample buffers for recording if needed
                }
            }
            
            // Mark session as running for simulator
            DispatchQueue.main.async {
                self.sessionState = .running
                print("✅ [Simulator] Mock camera session started")
            }
            return
        }
        #endif

        DispatchQueue.global(qos: .userInitiated).async {
            // Only setup capture session if we don't have one or if it's invalid
            if self._captureSession == nil {
                self.setupCaptureSession()
            }

            if let session = self._captureSession {
                if !session.isRunning {
                    session.startRunning()
                    print("🎬 AVCaptureSession started running")
                }

                DispatchQueue.main.async {
                    self.sessionState = .running
                    print("✅ Camera session started")
                }
            } else {
                DispatchQueue.main.async {
                    self.sessionState = .error(CameraError.sessionSetupFailed)
                    print("❌ Failed to create capture session")
                }
            }
        }
    }

    func stopSession() {
        guard sessionState != .stopped && sessionState != .stopping else {
            print("📹 Camera session already stopped or stopping")
            return
        }

        sessionState = .stopping

        DispatchQueue.global(qos: .userInitiated).async {
            // Just stop the session, don't destroy it
            // This allows for faster restart without reconfiguration
            if let session = self._captureSession, session.isRunning {
                session.stopRunning()
                print("🛑 AVCaptureSession stopped running")
            }

            DispatchQueue.main.async {
                self.sessionState = .stopped
                print("🛑 Camera session stopped (session retained for fast restart)")
            }
        }
    }

    /// Completely tear down the capture session (used for cleanup or camera switch)
    func destroySession() {
        sessionState = .stopping

        DispatchQueue.global(qos: .userInitiated).async {
            self._captureSession?.stopRunning()
            self._captureSession = nil

            DispatchQueue.main.async {
                self.sessionState = .stopped
                print("🛑 Camera session destroyed")
            }
        }
    }
}

// MARK: - DeviceDiscoveryProtocol Conformance
extension VideoManager {
    func startDeviceDiscovery() {
        setupDeviceDiscovery()
    }

    func stopDeviceDiscovery() {
        deviceDiscoverySession = nil
    }

    func resetDiscoveryFlags() {
        hasNewCameraDetected = false
        hasNewAudioDeviceDetected = false
    }
}

// MARK: - Private Methods
private extension VideoManager {
    func setupCamera() {
        // On simulator, use mock camera instead of trying to discover real cameras
        if isRunningOnSimulator {
            print("📱 [Simulator] Using mock camera - no real camera discovery")
            // Initialize simulator mock if needed
            #if targetEnvironment(simulator)
            if simulatorPreviewLayer == nil {
                if simulatorMock == nil {
                    simulatorMock = SimulatorCameraMock()
                }
                if let mockLayer = simulatorMock?.getPreviewLayer() {
                    simulatorPreviewLayer = mockLayer
                    print("✅ [Simulator] Created simulator mock preview layer")
                    simulatorMock?.startMockCamera { sampleBuffer in
                        print("📹 [Simulator] Received frame from mock camera")
                    }
                }
            }
            #endif
            // Mark session as running since we have a mock camera
            sessionState = .running
            return
        }

        // On real device, discover and select actual cameras
        discovereAndSelectCamera()
    }

    func discovereAndSelectCamera() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )

        availableCameras = discoverySession.devices

        // Only select external cameras (Openterface KVM device)
        if let externalCamera = availableCameras.first(where: { $0.deviceType == .external }) {
            selectedCamera = externalCamera
            currentDeviceName = externalCamera.localizedName
            hasNewCameraDetected = true
            print("📹 Selected external camera: \(externalCamera.localizedName)")
        } else if let externalCamera = availableCameras.first(where: { $0.position == .unspecified }) {
            selectedCamera = externalCamera
            currentDeviceName = externalCamera.localizedName
            hasNewCameraDetected = true
            print("📹 Selected unspecified position camera: \(externalCamera.localizedName)")
        } else {
            print("📹 No external camera connected")
        }

        print("📹 Found \(availableCameras.count) cameras")
        availableCameras.forEach { camera in
            print("  - \(camera.localizedName) (position: \(camera.position.rawValue), type: \(camera.deviceType.rawValue))")
        }

        // Setup capture session immediately when camera is selected and authorized
        if isAuthorized && selectedCamera != nil && _captureSession == nil {
            print("🔧 Setting up capture session for selected camera")
            DispatchQueue.global(qos: .userInitiated).async {
                self.setupCaptureSession()

                // Auto-start session after setup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if self.sessionState == .stopped {
                        self.startSession()
                    }
                }
            }
        }
    }

    func setupDeviceDiscovery() {
        deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )

        // Monitor for device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceWasConnected),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceWasDisconnected),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    func setupCaptureSession() {
        guard let selectedCamera = selectedCamera else {
            print("❌ No camera selected for setup")
            return
        }

        print("🔧 Setting up capture session for: \(selectedCamera.localizedName)")

        _captureSession = AVCaptureSession()
        guard let captureSession = _captureSession else {
            print("❌ Failed to create AVCaptureSession")
            return
        }

        captureSession.beginConfiguration()

        do {
            // Add video input
            let videoInput = try AVCaptureDeviceInput(device: selectedCamera)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                print("✅ Video input added successfully for: \(selectedCamera.localizedName)")
            } else {
                print("❌ Cannot add video input for: \(selectedCamera.localizedName)")
                captureSession.commitConfiguration()
                self._captureSession = nil
                return
            }

            // Note: We don't add AVCaptureVideoDataOutput here because we're using
            // AVCaptureVideoPreviewLayer directly for display. Adding an output with
            // nil delegate can cause frame timing issues and flickering.
            // The preview layer will handle video frames efficiently on its own.

            // Configure session preset
            if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
                print("✅ Session preset set to .high")
                updateCurrentResolution(from: .high)
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
                print("✅ Session preset set to .medium")
                updateCurrentResolution(from: .medium)
            } else {
                print("⚠️ Using default session preset")
                updateCurrentResolution(from: captureSession.sessionPreset)
            }

            captureSession.commitConfiguration()
            print("✅ Capture session configured successfully")

            // Configure video connection for stable frame delivery
            configureVideoConnection(for: captureSession)

            // Update zoom range for the new camera
            updateZoomRange()

        } catch {
            print("❌ Failed to setup capture session: \(error)")
            captureSession.commitConfiguration()
            self._captureSession = nil
        }
    }

    @objc func deviceWasConnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }

        DispatchQueue.main.async {
            if device.hasMediaType(.video) {
                self.hasNewCameraDetected = true
                self.discovereAndSelectCamera()
            }
        }
    }

    /// Configure video connection settings to prevent flickering and ensure stable frame delivery
    func configureVideoConnection(for captureSession: AVCaptureSession) {
        // Find the video input connection
        guard let videoInput = captureSession.inputs.first(where: { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.video)
        }) as? AVCaptureDeviceInput else {
            print("⚠️ No video input found for connection configuration")
            return
        }

        let device = videoInput.device

        // Configure device settings for stable capture
        do {
            try device.lockForConfiguration()

            // Disable automatic frame rate adjustment for more consistent delivery
            if device.activeFormat.videoSupportedFrameRateRanges.count > 0 {
                // Find a stable frame rate (prefer 30fps for external cameras)
                if let frameRateRange = device.activeFormat.videoSupportedFrameRateRanges.first(where: {
                    $0.maxFrameRate >= 30 && $0.minFrameRate <= 30
                }) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(30))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(30))
                    print("✅ Set consistent frame rate: 30fps")
                } else if let firstRange = device.activeFormat.videoSupportedFrameRateRanges.first {
                    // Use the device's preferred frame rate
                    let targetFPS = Int32(firstRange.maxFrameRate)
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: targetFPS)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: targetFPS)
                    print("✅ Set consistent frame rate: \(targetFPS)fps")
                }
            }

            // Disable low light boost if available (can cause flickering)
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = false
                print("✅ Disabled automatic low light boost")
            }

            // Set subject area change monitoring to false (reduces unnecessary adjustments)
            if device.isSubjectAreaChangeMonitoringEnabled {
                device.isSubjectAreaChangeMonitoringEnabled = false
                print("✅ Disabled subject area change monitoring")
            }

            device.unlockForConfiguration()
            print("✅ Video connection configured for stable frame delivery")
        } catch {
            print("⚠️ Failed to configure video connection: \(error)")
        }
    }

    @objc func deviceWasDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }

        DispatchQueue.main.async {
            if device.hasMediaType(.video) {
                self.discovereAndSelectCamera()
            }
        }
    }

    func cleanup() {
        destroySession()  // Use destroySession for complete cleanup
        deviceDiscoverySession = nil

        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Camera Session Manager Extension for Zoom
extension VideoManager {
    /// Set zoom factor for the current camera device
    func setZoomFactor(_ zoomFactor: CGFloat) {
        guard let device = selectedCamera else {
            print("⚠️ Cannot set zoom factor \(zoomFactor) - no selected camera")
            return
        }

        let clampedZoom = max(minZoomFactor, min(maxZoomFactor, zoomFactor))

        guard device.activeFormat.videoMaxZoomFactor >= clampedZoom else {
            print("⚠️ Zoom factor \(clampedZoom) exceeds device maximum")
            return
        }

        print("🔍 setZoomFactor called - requested: \(zoomFactor), clamped: \(clampedZoom), current: \(currentZoomFactor)")

        // Reset viewport to center when zooming out to 1.0 or less
        if clampedZoom <= 1.0 {
            viewportPosition = CGPoint.zero
            maxViewportOffset = CGPoint.zero
            print("🔍 Viewport reset to center (zoom <= 1.0)")
        }

        // Update the published property first (on main thread if needed)
        let oldZoom = currentZoomFactor
        if Thread.isMainThread {
            self.currentZoomFactor = clampedZoom
        } else {
            DispatchQueue.main.sync {
                self.currentZoomFactor = clampedZoom
            }
        }
        print("🔍 Updated currentZoomFactor from \(oldZoom) to \(self.currentZoomFactor)")

        // Don't apply hardware zoom to the device — the preview layer transform
        // handles zoom visually via CATransform3D, preserving full-resolution
        // content for panning within the zoomed view.
    }

    /// Get the available zoom range for the current camera
    func updateZoomRange() {
        guard let device = selectedCamera else {
            DispatchQueue.main.async {
                self.minZoomFactor = 1.0
                self.maxZoomFactor = 1.0
                self.currentZoomFactor = 1.0
            }
            return
        }

        let deviceMaxZoom = device.activeFormat.videoMaxZoomFactor
        let deviceCurrentZoom = device.videoZoomFactor

        DispatchQueue.main.async {
            self.minZoomFactor = 1.0
            // Limit max zoom to reasonable value (like 5x) or device max, whichever is smaller
            self.maxZoomFactor = min(5.0, deviceMaxZoom)
            // Only update current zoom if it's different (to avoid overriding user changes)
            if abs(self.currentZoomFactor - deviceCurrentZoom) > 0.01 {
                self.currentZoomFactor = deviceCurrentZoom
                print("🔍 Synced currentZoomFactor to device value: \(deviceCurrentZoom)")
            }
        }

        print("🔍 Zoom range updated - min: \(minZoomFactor), max: \(maxZoomFactor), current: \(currentZoomFactor), device: \(deviceCurrentZoom)")
    }

    /// Reset zoom to 1.0x
    func resetZoom() {
        setZoomFactor(1.0)
        resetViewport()
    }

    /// Update viewport position for panning when zoomed
    func updateViewportPosition(_ translation: CGPoint, viewBounds: CGRect) {
        guard currentZoomFactor > 1.0 else {
            // Reset viewport when not zoomed
            viewportPosition = CGPoint.zero
            return
        }

        // viewportPosition is the unscaled content point shown at screen center.
        // The valid range is half of the content area not visible at the current zoom:
        //   maxPan = viewSize × (zoom - 1) / (2 × zoom)
        let zoomScale = currentZoomFactor
        let maxPanX = viewBounds.width * (zoomScale - 1.0) / (2.0 * zoomScale)
        let maxPanY = viewBounds.height * (zoomScale - 1.0) / (2.0 * zoomScale)

        // Dragging the content right moves the visible viewport left.
        let newX = viewportPosition.x - translation.x / zoomScale
        let newY = viewportPosition.y - translation.y / zoomScale

        // Clamp the position to valid bounds (prevents showing black areas)
        let clampedX = max(-maxPanX, min(maxPanX, newX))
        let clampedY = max(-maxPanY, min(maxPanY, newY))

        // Update synchronously for immediate effect
        viewportPosition = CGPoint(x: clampedX, y: clampedY)
        maxViewportOffset = CGPoint(x: maxPanX, y: maxPanY)

        print("🔍 Viewport updated - position: (\(clampedX), \(clampedY)), max: (\(maxPanX), \(maxPanY)), zoom: \(zoomScale)")
    }

    /// Set viewport position directly (for absolute touch tracking)
    func setViewportPosition(_ position: CGPoint, viewBounds: CGRect) {
        guard currentZoomFactor > 1.0 else {
            viewportPosition = CGPoint.zero
            return
        }

        let zoomScale = currentZoomFactor
        let maxPanX = viewBounds.width * (zoomScale - 1.0) / (2.0 * zoomScale)
        let maxPanY = viewBounds.height * (zoomScale - 1.0) / (2.0 * zoomScale)

        let clampedX = max(-maxPanX, min(maxPanX, position.x))
        let clampedY = max(-maxPanY, min(maxPanY, position.y))

        viewportPosition = CGPoint(x: clampedX, y: clampedY)
        maxViewportOffset = CGPoint(x: maxPanX, y: maxPanY)
        print("🔍 setViewportPosition - requested: (\(position.x), \(position.y)), clamped: (\(clampedX), \(clampedY)), zoom: \(currentZoomFactor)")
    }

    /// Reset viewport position to center
    func resetViewport() {
        viewportPosition = CGPoint.zero
        maxViewportOffset = CGPoint.zero
        print("🔍 Viewport reset to center - position now: \(viewportPosition)")
    }

    /// Update current resolution string based on session preset
    private func updateCurrentResolution(from preset: AVCaptureSession.Preset) {
        switch preset {
        case .high:
            currentResolution = "1080p"
        case .medium:
            currentResolution = "720p"
        case .low:
            currentResolution = "480p"
        case .cif352x288:
            currentResolution = "CIF"
        case .vga640x480:
            currentResolution = "VGA"
        case .hd1280x720:
            currentResolution = "720p"
        case .hd1920x1080:
            currentResolution = "1080p"
        case .hd4K3840x2160:
            currentResolution = "2160p"
        default:
            currentResolution = "Unknown"
        }
        print("📐 Current resolution updated to: \(currentResolution)")
    }

    /// Set the camera session preset
    func setSessionPreset(_ preset: AVCaptureSession.Preset) {
        guard let captureSession = _captureSession else {
            print("❌ Cannot set preset: capture session not available")
            return
        }

        if captureSession.canSetSessionPreset(preset) {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = preset
            captureSession.commitConfiguration()
            updateCurrentResolution(from: preset)
            print("✅ Session preset set to \(preset.rawValue)")
        } else {
            print("❌ Cannot set session preset to \(preset.rawValue)")
        }
    }
}

// MARK: - Camera Session Manager Extension for Orientation
extension VideoManager {
    func cycleOrientationCorrection() {
        let allCases = OrientationCorrectionMode.allCases
        if let currentIndex = allCases.firstIndex(of: orientationCorrectionMode) {
            let nextIndex = (currentIndex + 1) % allCases.count
            orientationCorrectionMode = allCases[nextIndex]
        } else {
            orientationCorrectionMode = .normal
        }

        print("🔄 Orientation correction mode changed to: \(orientationCorrectionMode.description)")

        // Force refresh the preview layer orientation
        sessionId = UUID()
    }
}


