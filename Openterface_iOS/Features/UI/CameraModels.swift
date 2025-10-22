//
//  CameraModels.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import AVFoundation

/// Camera authorization status
enum CameraAuthorizationStatus {
    case notDetermined
    case restricted
    case denied
    case authorized
    
    init(from avStatus: AVAuthorizationStatus) {
        switch avStatus {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorized: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
    
    var isAuthorized: Bool {
        return self == .authorized
    }
    
    var description: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        }
    }
}

/// Audio authorization status
enum AudioAuthorizationStatus {
    case notDetermined
    case denied
    case authorized
    
    init(from avStatus: AVAudioSession.RecordPermission) {
        switch avStatus {
        case .undetermined: self = .notDetermined
        case .denied: self = .denied
        case .granted: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
    
    var isAuthorized: Bool {
        return self == .authorized
    }
    
    var description: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        }
    }
}

/// Camera device information
struct CameraDeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let deviceType: AVCaptureDevice.DeviceType
    let position: AVCaptureDevice.Position
    let isConnected: Bool
    let device: AVCaptureDevice
    
    init(device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.deviceType = device.deviceType
        self.position = device.position
        self.isConnected = device.isConnected
        self.device = device
    }
    
    var displayName: String {
        return name
    }
    
    var positionDescription: String {
        switch position {
        case .back: return "Back"
        case .front: return "Front"
        case .unspecified: return "External"
        @unknown default: return "Unknown"
        }
    }
    
    static func == (lhs: CameraDeviceInfo, rhs: CameraDeviceInfo) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Audio device information
struct AudioDeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool
    
    var displayName: String {
        return name
    }
    
    static func == (lhs: AudioDeviceInfo, rhs: AudioDeviceInfo) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Camera session state
enum CameraSessionState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(Error)
    
    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
    
    var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .error(let error): return "Error: \(error.localizedDescription)"
        }
    }
    
    // Equatable conformance for enum with associated values
    static func == (lhs: CameraSessionState, rhs: CameraSessionState) -> Bool {
        switch (lhs, rhs) {
        case (.stopped, .stopped), (.starting, .starting), (.running, .running), (.stopping, .stopping):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Orientation correction mode for external cameras
enum OrientationCorrectionMode: String, CaseIterable {
    case normal = "Normal"
    case inverted = "Inverted"
    
    var description: String {
        return self.rawValue
    }
}

/// Camera-related error types
enum CameraError: Error {
    case sessionSetupFailed
    case deviceNotFound
    case authorizationDenied
    case configurationFailed
    
    var localizedDescription: String {
        switch self {
        case .sessionSetupFailed:
            return "Failed to setup camera session"
        case .deviceNotFound:
            return "Camera device not found"
        case .authorizationDenied:
            return "Camera authorization denied"
        case .configurationFailed:
            return "Camera configuration failed"
        }
    }
}

// MARK: - Recording Models

/// Recording state
enum RecordingState: Equatable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
    case error(RecordingError)
    
    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
    
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .preparing: return "Preparing"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .stopping: return "Stopping"
        case .error(let error): return "Error: \(error.localizedDescription)"
        }
    }
    
    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.recording, .recording),
             (.paused, .paused), (.stopping, .stopping):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Recording-related error types
enum RecordingError: Error {
    case notAuthorized
    case sessionNotRunning
    case writerSetupFailed
    case writerError(Error)
    case fileSystemError(Error)
    case invalidState
    case photoOutputNotAvailable
    case captureError(Error)
    
    var localizedDescription: String {
        switch self {
        case .notAuthorized:
            return "Not authorized to access camera or photos"
        case .sessionNotRunning:
            return "Camera session is not running"
        case .writerSetupFailed:
            return "Failed to setup video writer"
        case .writerError(let error):
            return "Video writer error: \(error.localizedDescription)"
        case .fileSystemError(let error):
            return "File system error: \(error.localizedDescription)"
        case .invalidState:
            return "Invalid recording state"
        case .photoOutputNotAvailable:
            return "Photo output not available"
        case .captureError(let error):
            return "Capture error: \(error.localizedDescription)"
        }
    }
}

/// Recording configuration
struct RecordingConfiguration {
    /// Video codec type
    var videoCodec: AVVideoCodecType = .h264
    
    /// Video quality preset
    var videoQuality: VideoQuality = .high
    
    /// Whether to include audio
    var includeAudio: Bool = true
    
    /// Whether to save to photo library
    var saveToPhotoLibrary: Bool = true
    
    /// Custom output directory (if nil, uses default)
    var customOutputDirectory: URL? = nil
    
    /// Video quality options
    enum VideoQuality {
        case low
        case medium
        case high
        case maximum
        
        var bitrate: Int {
            switch self {
            case .low: return 2_500_000  // 2.5 Mbps
            case .medium: return 5_000_000  // 5 Mbps
            case .high: return 10_000_000  // 10 Mbps
            case .maximum: return 20_000_000  // 20 Mbps
            }
        }
        
        var description: String {
            switch self {
            case .low: return "Low (2.5 Mbps)"
            case .medium: return "Medium (5 Mbps)"
            case .high: return "High (10 Mbps)"
            case .maximum: return "Maximum (20 Mbps)"
            }
        }
    }
}

/// Recording information
struct RecordingInfo {
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
    let startTime: Date
    let endTime: Date
    
    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
