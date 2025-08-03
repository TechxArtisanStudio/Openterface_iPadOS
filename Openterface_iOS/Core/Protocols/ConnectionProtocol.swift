//
//  ConnectionProtocol.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import Combine

/// Protocol defining connection management capabilities
protocol ConnectionProtocol: ObservableObject {
    associatedtype DeviceType
    associatedtype ConnectionState
    
    /// Current connection state
    var connectionState: ConnectionState { get }
    
    /// Available devices
    var availableDevices: [DeviceType] { get }
    
    /// Connected devices
    var connectedDevices: Set<UUID> { get }
    
    /// Data transmission capability
    var dataTransmission: DataTransmissionProtocol { get }
    
    /// Start scanning for devices
    func startScanning()
    
    /// Stop scanning for devices
    func stopScanning()
    
    /// Connect to a specific device
    func connect(to device: DeviceType)
    
    /// Disconnect from a device
    func disconnect(from device: DeviceType)
    
    /// Check if permission is granted
    func checkPermission() -> Bool
    
    /// Request permission
    func requestPermission()
}

/// Protocol for data transmission over connections
protocol DataTransmissionProtocol {
    /// Send data over the connection
    func sendData(_ data: Data)
    
    /// Send data with completion handler
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void)
}

/// Protocol for monitoring connection quality
protocol ConnectionQualityProtocol {
    associatedtype QualityMetric
    
    /// Current connection quality metric (e.g., RSSI for Bluetooth)
    var qualityMetric: QualityMetric? { get }
    
    /// Start monitoring connection quality
    func startQualityMonitoring()
    
    /// Stop monitoring connection quality
    func stopQualityMonitoring()
}
