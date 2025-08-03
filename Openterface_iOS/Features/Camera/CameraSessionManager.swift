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
    
    // Audio processing
    private let audioQueue = DispatchQueue(label: "com.openterface.audio", qos: .userInteractive)
    
    // Simulator detection
    private var isRunningOnSimulator: Bool {
        return TARGET_OS_SIMULATOR != 0
    }
    
    // MARK: - Public Properties for UI
    var captureSession: AVCaptureSession? {
        return _captureSession
    }
    
    /// Check if an Openterface camera is currently connected and selected
    var hasOpenterfaceCamera: Bool {
        guard let selectedCamera = selectedCamera else { return false }
        
        // Check if the camera name contains "Openterface" (case insensitive)
        let cameraName = selectedCamera.localizedName.lowercased()
        return cameraName.contains("openterface")
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
    
    /// Debug method to check detailed audio authorization status
    func debugAudioAuthorization() {
        print("=== Audio Authorization Debug ===")
        let status = AVAudioSession.sharedInstance().recordPermission
        print("Current record permission: \(status)")
        print("Raw value: \(status.rawValue)")
        print("Current isAudioAuthorized: \(isAudioAuthorized)")
        print("Running on simulator: \(isRunningOnSimulator)")
        
        // Check audio session status
        let audioSession = AVAudioSession.sharedInstance()
        print("Audio session category: \(audioSession.category)")
        print("Audio session mode: \(audioSession.mode)")
        print("Audio session options: \(audioSession.categoryOptions)")
        
        // Try to get current route
        let currentRoute = audioSession.currentRoute
        print("Current audio route: \(currentRoute)")
        print("Input sources: \(currentRoute.inputs.count)")
        for input in currentRoute.inputs {
            print("  - Input: \(input.portName) (\(input.portType))")
        }
        print("Output sources: \(currentRoute.outputs.count)")
        for output in currentRoute.outputs {
            print("  - Output: \(output.portName) (\(output.portType))")
        }
        
        // Try to activate audio session to see if that makes inputs available
        do {
            try audioSession.setActive(true)
            print("✅ Audio session activation successful")
            
            // Check route again after activation
            let newRoute = audioSession.currentRoute
            print("After activation - Input sources: \(newRoute.inputs.count)")
            for input in newRoute.inputs {
                print("  - Input: \(input.portName) (\(input.portType))")
            }
        } catch {
            print("❌ Audio session activation failed: \(error)")
        }
        
        print("=== End Audio Debug ===")
    }
    
    /// Force refresh audio session and check authorization again
    func refreshAudioSession() {
        print("🔄 Refreshing audio session...")
        setupAudioSession()
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
        print("🎤 checkAudioAuthorization - raw status: \(status)")
        print("🎤 checkAudioAuthorization - status description: \(status.rawValue)")
        print("🎤 checkAudioAuthorization - current isAudioAuthorized: \(isAudioAuthorized)")
        print("🎤 checkAudioAuthorization - running on simulator: \(isRunningOnSimulator)")
        
        // Check all possible values for debugging
        switch status {
        case .undetermined:
            print("🎤 Status is .undetermined - user hasn't been asked for permission")
        case .denied:
            print("🎤 Status is .denied - user explicitly denied permission")
        case .granted:
            print("🎤 Status is .granted - user granted permission")
        @unknown default:
            print("🎤 Status is unknown: \(status)")
        }
        
        // Only check for available inputs if permission is granted
        var hasInputs = false
        if status == .granted {
            // Try to activate the audio session first to ensure inputs are available
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(true)
                print("🎤 Audio session activated for input check")
            } catch {
                print("🎤 Failed to activate audio session: \(error)")
            }
            
            // Now check for available audio inputs
            let currentRoute = audioSession.currentRoute
            hasInputs = currentRoute.inputs.count > 0
            print("🎤 Audio input sources available: \(hasInputs) (count: \(currentRoute.inputs.count))")
            
            // Log input details if available
            for input in currentRoute.inputs {
                print("  - Input: \(input.portName) (\(input.portType))")
            }
        }
        
        let wasAuthorized = self.isAudioAuthorized
        // Only consider audio authorized if permission is granted AND we have input sources
        let shouldBeAuthorized = (status == .granted) && hasInputs
        
        // Update immediately if on main queue, otherwise dispatch to main queue
        if Thread.isMainThread {
            self.isAudioAuthorized = shouldBeAuthorized
            print("🎤 checkAudioAuthorization - updated isAudioAuthorized from \(wasAuthorized) to \(self.isAudioAuthorized) (sync)")
        } else {
            DispatchQueue.main.sync {
                self.isAudioAuthorized = shouldBeAuthorized
                print("🎤 checkAudioAuthorization - updated isAudioAuthorized from \(wasAuthorized) to \(self.isAudioAuthorized) (async)")
            }
        }
        
        if status == .granted && hasInputs {
            print("✅ Audio is authorized and inputs available")
            
            // If we have a running session but no audio, restart it to add audio
            if sessionState == .running && _captureSession != nil {
                let currentInputCount = _captureSession?.inputs.count ?? 0
                let hasAudioInput = _captureSession?.inputs.contains { input in
                    if let deviceInput = input as? AVCaptureDeviceInput {
                        return deviceInput.device.hasMediaType(.audio)
                    }
                    return false
                } ?? false
                
                if !hasAudioInput {
                    print("🔄 Restarting session to add audio input...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.stopSession()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.startSession()
                        }
                    }
                } else {
                    print("ℹ️ Audio input already present in session")
                }
            }
        } else if status == .granted && !hasInputs {
            print("⚠️ Audio permission granted but no input sources available")
        } else if status == .undetermined {
            print("⚠️ Audio permission not determined - need to request permission")
        } else {
            print("❌ Audio not authorized - status: \(status)")
            if isRunningOnSimulator {
                print("📱 Note: Running on simulator - audio permissions may behave differently")
            }
        }
    }
    
    func requestAudioAccess() {
        print("🎤 requestAudioAccess called")
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("🎤 requestAudioAccess callback - granted: \(granted)")
            DispatchQueue.main.async {
                let wasAuthorized = self.isAudioAuthorized
                
                if granted {
                    print("✅ Audio permission granted, activating session and checking inputs...")
                    // Try to activate the audio session to make inputs available
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        print("✅ Audio session activated successfully")
                    } catch {
                        print("⚠️ Failed to activate audio session: \(error)")
                    }
                    
                    // Re-check authorization which will now also check for available inputs
                    self.checkAudioAuthorization()
                    
                    // Setup audio engine if we're now authorized
                    if self.isAudioAuthorized {
                        self.setupAudioEngine()
                        // If camera session is already running, restart it to add audio
                        if self.sessionState.isRunning {
                            self.stopSession()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self.startSession()
                            }
                        }
                    }
                } else {
                    print("❌ Audio access denied by user")
                    self.isAudioAuthorized = false
                }
                
                print("🎤 requestAudioAccess - updated isAudioAuthorized from \(wasAuthorized) to \(self.isAudioAuthorized)")
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
        
        print("🔊 toggleAudioMonitoring called")
        print("   - isAudioAuthorized: \(isAudioAuthorized)")
        print("   - current state: \(isAudioMonitoringEnabled)")
        
        guard isAudioAuthorized else {
            print("❌ Audio not authorized, requesting permission...")
            requestAudioAccess()
            return
        }
        
        isAudioMonitoringEnabled.toggle()
        print("🔊 Audio monitoring toggled to: \(isAudioMonitoringEnabled)")
        
        if isAudioMonitoringEnabled {
            // Setup audio engine if not already done
            if audioEngine == nil {
                print("🔧 Setting up audio engine...")
                setupAudioEngine()
            }
            print("🎵 Starting audio engine...")
            startAudioEngine()
        } else {
            print("🛑 Stopping audio engine...")
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
            
            print("✅ Audio engine started for monitoring")
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
        // Remove any installed taps
        audioEngine?.inputNode.removeTap(onBus: 0)
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
            
            // Try to activate the session to make microphone available for discovery
            do {
                try audioSession.setActive(true)
                print("✅ Audio session configured and activated")
            } catch {
                print("⚠️ Audio session configured but activation failed: \(error)")
                print("   This is normal if no audio permission has been granted yet")
            }
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
        
        guard isAudioAuthorized else {
            print("⚠️ Audio not authorized, skipping audio engine setup")
            return
        }
        
        do {
            audioEngine = AVAudioEngine()
            audioMixerNode = AVAudioMixerNode()
            
            guard let audioEngine = audioEngine,
                  let audioMixerNode = audioMixerNode else {
                print("❌ Failed to create audio components")
                return
            }
            
            audioEngine.attach(audioMixerNode)
            
            // Get the input and output nodes
            let inputNode = audioEngine.inputNode
            let outputNode = audioEngine.outputNode
            let format = inputNode.outputFormat(forBus: 0)
            
            // For simple monitoring, connect input directly to output via mixer
            audioEngine.connect(inputNode, to: audioMixerNode, format: format)
            audioEngine.connect(audioMixerNode, to: outputNode, format: format)
            
            // Store the format for later use
            audioFormat = format
            
            print("✅ Audio engine setup completed with direct input monitoring")
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
        
        // Also discover audio devices
        discoverAudioDevices()
        
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
    
    func discoverAudioDevices() {
        let audioDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )
        
        let audioDevices = audioDiscoverySession.devices
        print("🎤 Found \(audioDevices.count) audio devices")
        audioDevices.forEach { audioDevice in
            print("  - \(audioDevice.localizedName) (audio)")
        }
        
        // Set current audio device name if available
        if let firstAudioDevice = audioDevices.first {
            currentAudioDeviceName = firstAudioDevice.localizedName
            hasNewAudioDeviceDetected = true
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
            
            // Add audio input if available and authorized
            if isAudioAuthorized {
                print("🎤 Audio authorized, attempting to add audio input...")
                
                // Try to add audio input from the same device if it supports audio
                if selectedCamera.hasMediaType(.audio) {
                    print("🎤 Selected camera supports audio, adding audio input from camera...")
                    do {
                        let audioInput = try AVCaptureDeviceInput(device: selectedCamera)
                        if captureSession.canAddInput(audioInput) {
                            captureSession.addInput(audioInput)
                            print("✅ Audio input added from camera device: \(selectedCamera.localizedName)")
                        } else {
                            print("❌ Cannot add audio input from camera device")
                        }
                    } catch {
                        print("⚠️ Could not add audio input from camera device: \(error)")
                    }
                } else {
                    print("🎤 Camera doesn't support audio, looking for separate audio device...")
                    // Try to find a separate audio device
                    let audioDevices = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.external, .builtInMicrophone],
                        mediaType: .audio,
                        position: .unspecified
                    ).devices
                    
                    print("🎤 Found \(audioDevices.count) separate audio devices")
                    for device in audioDevices {
                        print("  - \(device.localizedName) (\(device.deviceType))")
                    }
                    
                    if let audioDevice = audioDevices.first {
                        print("🎤 Attempting to add audio input from: \(audioDevice.localizedName)")
                        do {
                            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                            if captureSession.canAddInput(audioInput) {
                                captureSession.addInput(audioInput)
                                currentAudioDeviceName = audioDevice.localizedName
                                print("✅ Audio input added from separate device: \(audioDevice.localizedName)")
                            } else {
                                print("❌ Cannot add audio input from separate device")
                            }
                        } catch {
                            print("⚠️ Could not add audio input from separate device: \(error)")
                        }
                    } else {
                        print("❌ No separate audio devices found")
                    }
                }
                
                // Add audio output for monitoring
                print("🎤 Adding audio output for monitoring...")
                let audioOutput = AVCaptureAudioDataOutput()
                audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
                if captureSession.canAddOutput(audioOutput) {
                    captureSession.addOutput(audioOutput)
                    self.audioOutput = audioOutput
                    print("✅ Audio output added successfully with delegate")
                } else {
                    print("❌ Cannot add audio output")
                }
            } else {
                print("⚠️ Audio not authorized, skipping audio setup")
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
            } else if device.hasMediaType(.audio) {
                self.hasNewAudioDeviceDetected = true
                self.discoverAudioDevices()
            }
        }
    }
    
    @objc func deviceWasDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        DispatchQueue.main.async {
            if device.hasMediaType(.video) {
                self.discovereAndSelectCamera()
            } else if device.hasMediaType(.audio) {
                self.discoverAudioDevices()
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

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
extension CameraSessionManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process audio if monitoring is enabled
        guard isAudioMonitoringEnabled else {
            return
        }
        
        // Print every 60 buffers to show activity without flooding console
        var bufferCount = 0
        bufferCount += 1
        if bufferCount % 60 == 0 {
            print("🎵 Processing audio buffer #\(bufferCount)")
        }
        
        // For now, just log that we're receiving audio - actual playback will be handled
        // by the audio engine's input monitoring
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
