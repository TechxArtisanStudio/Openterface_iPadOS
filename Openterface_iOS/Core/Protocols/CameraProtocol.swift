//
//  CameraProtocol.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import AVFoundation
import Combine

/// Protocol defining camera management capabilities
protocol CameraManagementProtocol: ObservableObject {
    /// Camera authorization state
    var isAuthorized: Bool { get }
    
    /// Audio authorization state
    var isAudioAuthorized: Bool { get }
    
    /// Available cameras
    var availableCameras: [AVCaptureDevice] { get }
    
    /// Currently selected camera
    var selectedCamera: AVCaptureDevice? { get set }
    
    /// Current camera device name
    var currentDeviceName: String? { get }
    
    /// Current audio device name
    var currentAudioDeviceName: String? { get }
    
    /// Session identifier for tracking changes
    var sessionId: UUID { get }
    
    /// Check camera authorization
    func checkCameraAuthorization()
    
    /// Request camera access
    func requestCameraAccess()
    
    /// Check audio authorization
    func checkAudioAuthorization()
    
    /// Request audio access
    func requestAudioAccess()
    
    /// Switch to a different camera
    func switchCamera(to device: AVCaptureDevice)
    
    /// Start camera session
    func startSession()
    
    /// Stop camera session
    func stopSession()
}

/// Protocol for audio monitoring and playback
protocol AudioManagementProtocol: ObservableObject {
    /// Audio monitoring state
    var isAudioMonitoringEnabled: Bool { get }
    
    /// Toggle audio monitoring
    func toggleAudioMonitoring()
    
    /// Start audio engine
    func startAudioEngine()
    
    /// Stop audio engine
    func stopAudioEngine()
    
    /// Configure audio session
    func configureAudioSession()
}

/// Protocol for device discovery and notification
protocol DeviceDiscoveryProtocol: ObservableObject {
    /// New camera detected flag
    var hasNewCameraDetected: Bool { get }
    
    /// New audio device detected flag
    var hasNewAudioDeviceDetected: Bool { get }
    
    /// Start device discovery
    func startDeviceDiscovery()
    
    /// Stop device discovery
    func stopDeviceDiscovery()
    
    /// Reset discovery flags
    func resetDiscoveryFlags()
}
