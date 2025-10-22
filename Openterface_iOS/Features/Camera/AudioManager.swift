//
//  AudioManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import AVFoundation
import Combine

final class AudioManager: NSObject, ObservableObject, AudioManagementProtocol, DeviceDiscoveryProtocol {
    // MARK: - Published Properties
    @Published var isAudioAuthorized = false
    @Published var currentAudioDeviceName: String?
    @Published var isAudioMonitoringEnabled = false
    @Published var hasNewAudioDeviceDetected = false
    
    // Camera device detection (not used by AudioManager, but required by protocol)
    @Published var hasNewCameraDetected = false

    // MARK: - Private Properties
    // Audio capture session management
    private weak var captureSession: AVCaptureSession?
    private var audioInput: AVCaptureDeviceInput?
    
    // Audio engine for playback monitoring
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var mixerNode: AVAudioMixerNode?
    
    private var lastToggleTime: Date = Date.distantPast

    // Simulator detection
    private var isRunningOnSimulator: Bool {
        return TARGET_OS_SIMULATOR != 0
    }

    override init() {
        super.init()
        print("🎤 AudioManager init - starting setup")
        setupAudioSession()
        checkAudioAuthorization()
        print("🎤 AudioManager init - completed, isAudioAuthorized: \(isAudioAuthorized)")
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods for Coordination
    /// Prepare audio but don't add to capture session yet
    /// Audio will be added either for monitoring (AVAudioEngine) or recording (AVCaptureSession)
    func addAudioToCaptureSession(_ captureSession: AVCaptureSession) {
        guard isAudioAuthorized else {
            print("⚠️ Audio not authorized, skipping audio setup")
            return
        }

        print("🎤 Preparing audio system...")
        self.captureSession = captureSession

        // Detect available audio devices
        let audioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        print("🎤 Found \(audioDevices.count) audio devices")
        for device in audioDevices {
            print("  - \(device.localizedName) (\(device.deviceType))")
        }

        if let audioDevice = audioDevices.first {
            currentAudioDeviceName = audioDevice.localizedName
            print("✅ Audio device available: \(audioDevice.localizedName)")
        } else {
            print("❌ No audio devices found")
        }

        print("✅ Audio system ready - monitoring starts muted, can be enabled by user")
    }
}

// MARK: - AudioManagementProtocol Conformance
extension AudioManager {
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
            print("🔧 Setting up audio engine for monitoring...")
            setupAudioEngine()
            print("🎵 Starting audio engine...")
            startAudioEngine()
        } else {
            print("🛑 Stopping audio engine...")
            stopAudioEngine()
        }

        print("🔊 Audio monitoring: \(isAudioMonitoringEnabled ? "ON" : "OFF")")
    }

    func startAudioEngine() {
        guard let audioEngine = audioEngine else {
            print("⚠️ Audio engine not available")
            return
        }
        
        guard !audioEngine.isRunning else {
            print("⚠️ Audio engine already running")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
            print("✅ Audio engine started for monitoring")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    func stopAudioEngine() {
        guard let audioEngine = audioEngine, audioEngine.isRunning else {
            print("⚠️ Audio engine not running")
            return
        }
        
        audioEngine.stop()
        print("🛑 Audio engine stopped")
        
        // Clean up engine for fresh start next time
        self.audioEngine = nil
        self.playerNode = nil
        self.audioFormat = nil
        self.mixerNode = nil
    }

    func configureAudioSession() {
        setupAudioSession()
    }
    
    func setupAudioEngine() {
        guard !isRunningOnSimulator else {
            print("📱 Skipping audio engine setup on simulator")
            return
        }

        guard isAudioAuthorized else {
            print("⚠️ Audio not authorized, skipping audio engine setup")
            return
        }

        do {
            // Create fresh audio engine
            audioEngine = AVAudioEngine()
            
            guard let audioEngine = audioEngine else {
                print("❌ Failed to create audio engine")
                return
            }

            // Get input and output nodes
            let inputNode = audioEngine.inputNode
            let outputNode = audioEngine.outputNode
            
            // Get the hardware formats
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let outputFormat = outputNode.inputFormat(forBus: 0)
            
            print("🎵 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
            print("🎵 Output format: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount) channels")
            
            // Validate formats
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                print("❌ Invalid input format")
                return
            }
            
            guard outputFormat.sampleRate > 0 && outputFormat.channelCount > 0 else {
                print("❌ Invalid output format")
                return
            }
            
            // Create a compatible format
            let format: AVAudioFormat?
            if inputFormat.sampleRate == outputFormat.sampleRate {
                format = inputFormat
                print("🎵 Using input format (matching sample rates)")
            } else {
                let commonSampleRate = min(inputFormat.sampleRate, outputFormat.sampleRate)
                let commonChannels = min(inputFormat.channelCount, outputFormat.channelCount)
                format = AVAudioFormat(standardFormatWithSampleRate: commonSampleRate, channels: commonChannels)
                print("🎵 Created common format: \(commonSampleRate)Hz, \(commonChannels) channels")
            }
            
            guard let validFormat = format, validFormat.sampleRate > 0 && validFormat.channelCount > 0 else {
                print("❌ Cannot create compatible audio format")
                return
            }
            
            // Create mixer node for volume control
            let mixer = AVAudioMixerNode()
            audioEngine.attach(mixer)
            self.mixerNode = mixer
            
            // Connect input -> mixer -> output for passthrough monitoring with volume control
            audioEngine.connect(inputNode, to: mixer, format: validFormat)
            audioEngine.connect(mixer, to: outputNode, format: validFormat)
            print("✅ Connected audio input -> mixer -> output with format: \(validFormat.sampleRate)Hz, \(validFormat.channelCount) channels")
            
            self.audioFormat = validFormat
            print("✅ Audio engine setup completed with volume control")
        } catch {
            print("❌ Failed to setup audio engine: \(error)")
            audioEngine = nil
            playerNode = nil
            audioFormat = nil
            mixerNode = nil
        }
    }
    
    func cleanup() {
        stopAudioEngine()
        audioInput = nil
        captureSession = nil
    }
    
    /// Lower volume to zero instantly (for recording start)
    func lowerVolumeToZero() {
        guard let mixer = mixerNode else {
            print("⚠️ No mixer node for volume control")
            return
        }
        
        mixer.outputVolume = 0.0
        print("🔇 Volume lowered to 0")
    }
    
    /// Gradually restore volume to normal (after recording stabilizes)
    func restoreVolumeGradually(delay: TimeInterval = 3.0, duration: TimeInterval = 0.1) {
        guard let mixer = mixerNode else {
            print("⚠️ No mixer node for volume control")
            return
        }
        
        print("🔊 Scheduling volume restore in \(delay)s")
        
        // Wait for the delay, then fade volume back
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let mixer = self.mixerNode else { return }
            
            print("🔊 Starting volume fade from 0 to 1.0 over \(duration)s")
            
            // Animate volume increase on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                let steps = 20
                let stepDuration = duration / Double(steps)
                
                for i in 0...steps {
                    let progress = Double(i) / Double(steps)
                    let volume = Float(progress)
                    
                    DispatchQueue.main.async {
                        mixer.outputVolume = volume
                    }
                    
                    if i < steps {
                        Thread.sleep(forTimeInterval: stepDuration)
                    }
                }
                
                DispatchQueue.main.async {
                    print("✅ Volume restored to 1.0")
                }
            }
        }
    }
    
    /// Set volume immediately
    func setVolume(_ volume: Float) {
        guard let mixer = mixerNode else {
            print("⚠️ No mixer node for volume control")
            return
        }
        
        let clampedVolume = max(0.0, min(1.0, volume))
        mixer.outputVolume = clampedVolume
        print("🔊 Volume set to \(clampedVolume)")
    }
}

// MARK: - Audio Authorization Methods
extension AudioManager {
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

            // Setup audio engine if we're now authorized
            setupAudioEngine()
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
                    }
                } else {
                    print("❌ Audio access denied by user")
                    self.isAudioAuthorized = false
                }

                print("🎤 requestAudioAccess - updated isAudioAuthorized from \(wasAuthorized) to \(self.isAudioAuthorized)")
            }
        }
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
}

// MARK: - Private Methods
private extension AudioManager {
    func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use a simpler configuration that's more compatible with camera apps
            // .mixWithOthers allows audio to play through speakers even when not actively monitoring
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
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
}

// MARK: - DeviceDiscoveryProtocol Conformance
extension AudioManager {
    func startDeviceDiscovery() {
        print("🔊 AudioManager: Starting audio device discovery")
        
        // For audio devices, we mainly monitor the built-in microphone
        // Audio device discovery is simpler than video devices
        checkAudioDevices()
        
        // Set up audio session interruption notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    func stopDeviceDiscovery() {
        print("🛑 AudioManager: Stopping audio device discovery")
        
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    func resetDiscoveryFlags() {
        hasNewAudioDeviceDetected = false
        hasNewCameraDetected = false
    }
    
    private func checkAudioDevices() {
        // Check available audio inputs
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            let inputs = audioSession.availableInputs ?? []
            
            print("🎤 Found \(inputs.count) audio inputs")
            
            // Update current audio device name
            if let preferredInput = audioSession.preferredInput {
                currentAudioDeviceName = preferredInput.portName
            } else if let firstInput = inputs.first {
                currentAudioDeviceName = firstInput.portName
            }
            
        } catch {
            print("❌ Failed to check audio devices: \(error)")
        }
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        print("🎤 Audio session interruption detected")
        // Handle audio session interruptions (e.g., phone calls)
        hasNewAudioDeviceDetected = true
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        print("🎤 Audio route change detected")
        // Handle audio route changes (e.g., headphones plugged in/out)
        hasNewAudioDeviceDetected = true
        checkAudioDevices()
    }
}
