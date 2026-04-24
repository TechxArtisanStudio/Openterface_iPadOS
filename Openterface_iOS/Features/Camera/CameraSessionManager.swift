//
//  CameraSessionManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import AVFoundation
import Combine

final class CameraSessionManager: NSObject, ObservableObject {
    // MARK: - Sub-managers
    private let videoManager: VideoManager
    private let audioManager: AudioManager
    private let recordingManager: RecordingManager
    
    // MARK: - Published Properties (Delegated)
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
    @Published var orientationCorrectionMode: OrientationCorrectionMode = .normal
    
    // Zoom properties
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 5.0
    
    // Viewport position properties for panning when zoomed
    @Published var viewportPosition: CGPoint = CGPoint.zero
    @Published var maxViewportOffset: CGPoint = CGPoint.zero
    
    // Resolution property
    @Published var currentResolution: String = "1080p"
    
    // Recording properties
    @Published var recordingState: RecordingState = .idle
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var lastRecordingInfo: RecordingInfo?
    @Published var lastScreenshotURL: URL?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Properties for UI
    var captureSession: AVCaptureSession? {
        return videoManager.captureSession
    }
    
    /// Check if an Openterface camera is currently connected and selected
    var hasOpenterfaceCamera: Bool {
        return videoManager.hasOpenterfaceCamera
    }
    
    /// Get or create a preview layer for the current capture session
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return videoManager.getPreviewLayer()
    }
    
    #if targetEnvironment(simulator)
    /// Get simulator preview layer (for testing on simulator)
    func getSimulatorPreviewLayer() -> CALayer? {
        return videoManager.getSimulatorPreviewLayer()
    }
    
    /// Check if running in simulator mode
    var isSimulatorMode: Bool {
        return TARGET_OS_SIMULATOR != 0
    }
    
    /// Capture screenshot from simulator mock camera
    func captureSimulatorScreenshot() -> UIImage? {
        return videoManager.captureSimulatorScreenshot()
    }
    #endif
    
    override init() {
        // Initialize sub-managers
        videoManager = VideoManager()
        audioManager = AudioManager()
        recordingManager = RecordingManager()
        
        super.init()
        
        print("🎬 CameraSessionManager init - starting setup")
        setupBindings()
        print("🎬 CameraSessionManager init - completed")
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Bind VideoManager properties
        videoManager.$isAuthorized.assign(to: &$isAuthorized)
        videoManager.$availableCameras.assign(to: &$availableCameras)
        videoManager.$selectedCamera.assign(to: &$selectedCamera)
        videoManager.$currentDeviceName.assign(to: &$currentDeviceName)
        videoManager.$sessionId.assign(to: &$sessionId)
        videoManager.$sessionState.assign(to: &$sessionState)
        videoManager.$hasNewCameraDetected.assign(to: &$hasNewCameraDetected)
        videoManager.$orientationCorrectionMode.assign(to: &$orientationCorrectionMode)
        videoManager.$currentZoomFactor.assign(to: &$currentZoomFactor)
        videoManager.$minZoomFactor.assign(to: &$minZoomFactor)
        videoManager.$maxZoomFactor.assign(to: &$maxZoomFactor)
        videoManager.$viewportPosition.assign(to: &$viewportPosition)
        videoManager.$maxViewportOffset.assign(to: &$maxViewportOffset)
        videoManager.$currentResolution.assign(to: &$currentResolution)
        
        // Bind AudioManager properties
        audioManager.$isAudioAuthorized.assign(to: &$isAudioAuthorized)
        audioManager.$currentAudioDeviceName.assign(to: &$currentAudioDeviceName)
        audioManager.$isAudioMonitoringEnabled.assign(to: &$isAudioMonitoringEnabled)
        audioManager.$hasNewAudioDeviceDetected.assign(to: &$hasNewAudioDeviceDetected)
        
        // Bind RecordingManager properties
        recordingManager.$recordingState.assign(to: &$recordingState)
        recordingManager.$currentRecordingDuration.assign(to: &$currentRecordingDuration)
        recordingManager.$lastRecordingInfo.assign(to: &$lastRecordingInfo)
        recordingManager.$lastScreenshotURL.assign(to: &$lastScreenshotURL)
        
        // Sync orientation correction mode to recording manager
        videoManager.$orientationCorrectionMode
            .sink { [weak self] mode in
                self?.recordingManager.orientationCorrectionMode = mode
            }
            .store(in: &cancellables)
        
        // Setup recording manager when session is available
        videoManager.$sessionState
            .sink { [weak self] state in
                if state.isRunning, let session = self?.videoManager.captureSession {
                    self?.recordingManager.setup(with: session)
                }
            }
            .store(in: &cancellables)
    }
    
    private func cleanup() {
        cancellables.removeAll()
    }
}

// MARK: - CameraManagementProtocol Conformance
extension CameraSessionManager: CameraManagementProtocol {
    func checkCameraAuthorization() {
        videoManager.checkCameraAuthorization()
    }
    
    /// Force refresh authorization status - useful for debugging
    func forceRefreshAuthorization() {
        print("🔄 Force refreshing authorization status...")
        videoManager.checkCameraAuthorization()
        audioManager.checkAudioAuthorization()
    }
    
    /// Debug method to check detailed audio authorization status
    func debugAudioAuthorization() {
        audioManager.debugAudioAuthorization()
    }
    
    /// Force refresh audio session and check authorization again
    func refreshAudioSession() {
        audioManager.refreshAudioSession()
    }
    
    func requestCameraAccess() {
        videoManager.requestCameraAccess()
    }
    
    func checkAudioAuthorization() {
        audioManager.checkAudioAuthorization()
    }
    
    func requestAudioAccess() {
        audioManager.requestAudioAccess()
    }
    
    func switchCamera(to device: AVCaptureDevice) {
        videoManager.switchCamera(to: device)
    }
    
    func startSession() {
        guard videoManager.isAuthorized else {
            print("❌ Camera not authorized")
            return
        }
        
        // Start video session first
        videoManager.startSession()
        
        // If audio is authorized, add audio to the session
        if audioManager.isAudioAuthorized, let captureSession = videoManager.captureSession {
            audioManager.addAudioToCaptureSession(captureSession)
        }
    }
    
    func stopSession() {
        videoManager.stopSession()
    }
    
    /// Completely tear down the capture session (used for cleanup or camera switch)
    func destroySession() {
        videoManager.destroySession()
    }
}

// MARK: - AudioManagementProtocol Conformance
extension CameraSessionManager: AudioManagementProtocol {
    func toggleAudioMonitoring() {
        audioManager.toggleAudioMonitoring()
    }
    
    func startAudioEngine() {
        audioManager.startAudioEngine()
    }
    
    func stopAudioEngine() {
        audioManager.stopAudioEngine()
    }
    
    func configureAudioSession() {
        audioManager.configureAudioSession()
    }
}

// MARK: - DeviceDiscoveryProtocol Conformance
extension CameraSessionManager: DeviceDiscoveryProtocol {
    func startDeviceDiscovery() {
        videoManager.startDeviceDiscovery()
        audioManager.startDeviceDiscovery()
    }
    
    func stopDeviceDiscovery() {
        videoManager.stopDeviceDiscovery()
        audioManager.stopDeviceDiscovery()
    }
    
    func resetDiscoveryFlags() {
        videoManager.resetDiscoveryFlags()
        audioManager.resetDiscoveryFlags()
    }
}

// MARK: - Zoom and Viewport Methods (Delegated to VideoManager)
extension CameraSessionManager {
    /// Set zoom factor for the current camera device
    func setZoomFactor(_ zoomFactor: CGFloat) {
        videoManager.setZoomFactor(zoomFactor)
    }
    
    /// Get the available zoom range for the current camera
    func updateZoomRange() {
        videoManager.updateZoomRange()
    }
    
    /// Reset zoom to 1.0x
    func resetZoom() {
        videoManager.resetZoom()
    }
    
    /// Update viewport position for panning when zoomed
    func updateViewportPosition(_ translation: CGPoint, viewBounds: CGRect) {
        videoManager.updateViewportPosition(translation, viewBounds: viewBounds)
    }
    
    /// Reset viewport position to center
    func resetViewport() {
        videoManager.resetViewport()
    }
    
    /// Set the camera session preset
    func setSessionPreset(_ preset: AVCaptureSession.Preset) {
        videoManager.setSessionPreset(preset)
    }
}

// MARK: - Orientation Methods (Delegated to VideoManager)
extension CameraSessionManager {
    func cycleOrientationCorrection() {
        videoManager.cycleOrientationCorrection()
    }
}

// MARK: - Recording Methods (Delegated to RecordingManager)
extension CameraSessionManager: RecordingManagementProtocol {
    /// Start video recording
    func startRecording() {    
        recordingManager.startRecording()
    }
    
    /// Stop video recording
    func stopRecording(completion: ((Result<RecordingInfo, RecordingError>) -> Void)? = nil) {
        recordingManager.stopRecording(completion: completion)
    }
    
    /// Capture a screenshot from the current camera feed
    func captureScreenshot(completion: ((Result<URL, RecordingError>) -> Void)? = nil) {
        recordingManager.captureScreenshot(completion: completion)
    }
    
    /// Get recording configuration
    var recordingConfiguration: RecordingConfiguration {
        get { recordingManager.configuration }
        set { recordingManager.configuration = newValue }
    }
    
    /// Update recording configuration
    func updateRecordingConfiguration(_ configuration: RecordingConfiguration) {
        recordingManager.configuration = configuration
    }
    
    /// Get the directory where recordings and screenshots are saved
    func getRecordingsDirectory() -> URL {
        return recordingManager.getRecordingsDirectory()
    }
    
    /// Get a user-friendly description of where files are saved
    func getSaveLocationDescription() -> String {
        return recordingManager.getSaveLocationDescription()
    }
    
    /// Request photo library permission
    func requestPhotoLibraryPermission(completion: ((Bool) -> Void)? = nil) {
        recordingManager.requestPhotoLibraryPermission(completion: completion)
    }
}
