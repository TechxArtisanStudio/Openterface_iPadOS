//
//  CameraSessionManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import AVFoundation
import Combine
import UIKit

final class CameraSessionManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthorized = false {
        didSet {
            print("🔄 isAuthorized changed from \(oldValue) to \(isAuthorized)")
        }
    }
    @Published var isAudioAuthorized = false
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var currentDeviceName: String?
    @Published var currentAudioDeviceName: String?
    @Published var sessionId = UUID()
    @Published var sessionState: CameraSessionState = .stopped
    @Published var isAudioMonitoringEnabled = false
    @Published var hasNewCameraDetected = false
    @Published var hasNewAudioDeviceDetected = false
    
    // Orientation correction for external cameras
    @Published var orientationCorrectionMode: OrientationCorrectionMode = .inverted
    
    // MARK: - Private Properties
    private var _captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var deviceDiscoverySession: AVCaptureDevice.DiscoverySession?
    
    // Audio components
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var audioMixerNode: AVAudioMixerNode?
    private var lastToggleTime: Date = Date.distantPast
    
    // Simulator detection
    private var isRunningOnSimulator: Bool {
        return TARGET_OS_SIMULATOR != 0
    }
    
    // MARK: - Public Properties for UI
    var captureSession: AVCaptureSession? {
        return _captureSession
    }
    
    /// Get or create a preview layer for the current capture session
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        print("🎬 === getPreviewLayer called ===")
        
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
        previewLayer.videoGravity = .resizeAspectFill
        
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

    
    override init() {
        super.init()
        print("🎬 CameraSessionManager init - starting setup")
        setupAudioSession()
        // Audio engine setup is now done on-demand when audio monitoring is enabled
        print("🎬 CameraSessionManager init - checking initial authorization")
        checkCameraAuthorization()
        checkAudioAuthorization()
        setupDeviceDiscovery()
        print("🎬 CameraSessionManager init - completed, isAuthorized: \(isAuthorized)")
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - CameraManagementProtocol Conformance
extension CameraSessionManager: CameraManagementProtocol {
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
        let shouldBeAuthorized = (status == .authorized)
        
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
        checkAudioAuthorization()
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
    
    func checkAudioAuthorization() {
        let status = AVAudioSession.sharedInstance().recordPermission
        DispatchQueue.main.async {
            self.isAudioAuthorized = (status == .granted)
        }
    }
    
    func requestAudioAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.isAudioAuthorized = granted
                if granted {
                    self.setupAudioEngine()
                }
            }
        }
    }
    
    func switchCamera(to device: AVCaptureDevice) {
        selectedCamera = device
        currentDeviceName = device.localizedName
        sessionId = UUID()
        
        if sessionState.isRunning {
            stopSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startSession()
            }
        }
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
        
        sessionState = .starting
        
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
        sessionState = .stopping
        
        DispatchQueue.global(qos: .userInitiated).async {
            self._captureSession?.stopRunning()
            self._captureSession = nil
            
            DispatchQueue.main.async {
                self.sessionState = .stopped
                print("🛑 Camera session stopped")
            }
        }
    }
}

// MARK: - AudioManagementProtocol Conformance
extension CameraSessionManager: AudioManagementProtocol {
    func toggleAudioMonitoring() {
        // Prevent rapid toggling
        let now = Date()
        guard now.timeIntervalSince(lastToggleTime) > 1.0 else {
            print("⚠️ Audio toggle too rapid, ignoring")
            return
        }
        lastToggleTime = now
        
        isAudioMonitoringEnabled.toggle()
        
        if isAudioMonitoringEnabled {
            // Setup audio engine if not already done
            if audioEngine == nil {
                setupAudioEngine()
            }
            startAudioEngine()
        } else {
            stopAudioEngine()
        }
        
        print("🔊 Audio monitoring: \(isAudioMonitoringEnabled ? "ON" : "OFF")")
    }
    
    func startAudioEngine() {
        guard let audioEngine = audioEngine, !audioEngine.isRunning else { 
            print("⚠️ Audio engine already running or not available")
            return 
        }
        
        do {
            // Ensure audio session is active before starting engine
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
            print("✅ Audio engine started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
            // Only try to recover if we haven't already tried recently
            let now = Date()
            if now.timeIntervalSince(lastToggleTime) > 5.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.setupAudioEngine()
                }
            }
        }
    }
    
    func stopAudioEngine() {
        audioEngine?.stop()
        print("🛑 Audio engine stopped")
    }
    
    func configureAudioSession() {
        setupAudioSession()
    }
}

// MARK: - DeviceDiscoveryProtocol Conformance
extension CameraSessionManager: DeviceDiscoveryProtocol {
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
private extension CameraSessionManager {
    func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use a simpler configuration that's more compatible with camera apps
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setPreferredSampleRate(44100.0)
            try audioSession.setPreferredIOBufferDuration(0.02)
            // Don't activate the session immediately - let it be activated when needed
            print("✅ Audio session configured (not activated)")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
    
    func setupAudioEngine() {
        // Only setup audio engine if we're planning to use audio features
        // This prevents crashes when audio engine is not needed
        guard !isRunningOnSimulator else {
            print("📱 Skipping audio engine setup on simulator")
            return
        }
        
        do {
            audioEngine = AVAudioEngine()
            audioPlayerNode = AVAudioPlayerNode()
            audioMixerNode = AVAudioMixerNode()
            
            guard let audioEngine = audioEngine,
                  let audioPlayerNode = audioPlayerNode,
                  let audioMixerNode = audioMixerNode else {
                print("❌ Failed to create audio components")
                return
            }
            
            audioEngine.attach(audioPlayerNode)
            audioEngine.attach(audioMixerNode)
            
            // Create connections to ensure audio engine has proper input/output setup
            let inputNode = audioEngine.inputNode
            let outputNode = audioEngine.outputNode
            let format = inputNode.outputFormat(forBus: 0)
            
            // Connect mixer to output
            audioEngine.connect(audioMixerNode, to: outputNode, format: format)
            
            // Store the format for later use
            audioFormat = format
            
            print("✅ Audio engine setup completed with proper connections")
        } catch {
            print("❌ Failed to setup audio engine: \(error)")
            // Clear references if setup failed
            audioEngine = nil
            audioPlayerNode = nil
            audioMixerNode = nil
            audioFormat = nil
        }
    }
    
    func setupCamera() {
        discovereAndSelectCamera()
    }
    
    func discovereAndSelectCamera() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        availableCameras = discoverySession.devices
        
        // Select external camera if available, otherwise built-in
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
        } else if let builtInCamera = availableCameras.first {
            selectedCamera = builtInCamera
            currentDeviceName = builtInCamera.localizedName
            print("📹 Selected built-in camera: \(builtInCamera.localizedName)")
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
            
            // Add video output for preview
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                self.videoOutput = videoOutput
                print("✅ Video output added successfully")
            } else {
                print("❌ Cannot add video output")
            }
            
            // Configure session preset
            if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
                print("✅ Session preset set to .high")
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
                print("✅ Session preset set to .medium")
            } else {
                print("⚠️ Using default session preset")
            }
            
            captureSession.commitConfiguration()
            print("✅ Capture session configured successfully")
            
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
    
    @objc func deviceWasDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        DispatchQueue.main.async {
            if device.hasMediaType(.video) {
                self.discovereAndSelectCamera()
            }
        }
    }
    
    func cleanup() {
        stopSession()
        stopAudioEngine()
        deviceDiscoverySession = nil
        
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Custom Errors
enum CameraError: LocalizedError {
    case sessionSetupFailed
    case deviceNotAvailable
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .sessionSetupFailed:
            return "Failed to setup camera session"
        case .deviceNotAvailable:
            return "Camera device not available"
        case .permissionDenied:
            return "Camera permission denied"
        }
    }
}

// MARK: - Camera Session Manager Extension for Orientation
extension CameraSessionManager {
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
