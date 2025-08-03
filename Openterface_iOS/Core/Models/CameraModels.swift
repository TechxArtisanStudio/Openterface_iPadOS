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
    case rotated180 = "Rotated 180°"
    case mirroredInverted = "Mirrored + Inverted"
    
    var description: String {
        return self.rawValue
    }
}
