//
//  ConnectionModels.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreBluetooth

/// Bluetooth connection state
enum BluetoothConnectionState {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
    
    init(from cbState: CBManagerState) {
        switch cbState {
        case .unknown: self = .unknown
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        @unknown default: self = .unknown
        }
    }
    
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "Powered Off"
        case .poweredOn: return "Powered On"
        }
    }
    
    var isReady: Bool {
        return self == .poweredOn
    }
}

/// Bluetooth device model
struct BluetoothDevice: Identifiable, Hashable {
    let id: UUID
    let name: String?
    let rssi: NSNumber
    let peripheral: CBPeripheral
    
    init(peripheral: CBPeripheral, rssi: NSNumber) {
        self.id = peripheral.identifier
        self.name = peripheral.name
        self.rssi = rssi
        self.peripheral = peripheral
    }
    
    var displayName: String {
        return name ?? "Unknown Device"
    }
    
    var signalStrength: SignalStrength {
        let value = rssi.intValue
        switch value {
        case -50...0: return .excellent
        case -70..<(-50): return .good
        case -90..<(-70): return .fair
        default: return .poor
        }
    }
    
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Signal strength enum
enum SignalStrength: CaseIterable {
    case excellent
    case good
    case fair
    case poor
    
    var icon: String {
        switch self {
        case .excellent: return "wifi"
        case .good: return "wifi"
        case .fair: return "wifi"
        case .poor: return "wifi.slash"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}
