//
//  BluetoothConnectionManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreBluetooth
import Combine
import SwiftUI

final class BluetoothConnectionManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: BluetoothConnectionState = .unknown
    @Published var availableDevices: [BluetoothDevice] = []
    @Published var connectedDevices: Set<UUID> = []
    @Published var qualityMetric: NSNumber? = nil
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var fff2Characteristic: CBCharacteristic?
    private var initializationTimer: Timer?
    private var qualityMonitoringTimer: Timer?
    
    // MARK: - UI Binding
    var showPopupBinding: Binding<Bool>?
    
    // MARK: - Constants
    private let openterfaceDevicePrefix = "openterface"
    private let fff2CharacteristicUUID = CBUUID(string: "FFF2")
    
    override init() {
        super.init()
        setupCentralManager()
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - ConnectionProtocol Conformance
extension BluetoothConnectionManager: ConnectionProtocol {
    typealias DeviceType = BluetoothDevice
    typealias ConnectionState = BluetoothConnectionState
    
    var dataTransmission: DataTransmissionProtocol {
        return self
    }
    
    func startScanning() {
        print("🔍 Starting BLE scanning...")
        availableDevices.removeAll()
        
        guard let centralManager = centralManager else {
            print("❌ Cannot start scanning - CBCentralManager not initialized")
            return
        }
        
        guard connectionState.isReady else {
            print("❌ Cannot start scanning - Bluetooth state: \(connectionState.description)")
            handleBluetoothNotReady()
            return
        }
        
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        print("✅ BLE scanning started successfully")
    }
    
    func stopScanning() {
        print("🛑 Stopping BLE scanning...")
        centralManager?.stopScan()
    }
    
    func connect(to device: BluetoothDevice) {
        print("🔗 Connecting to \(device.displayName)")
        guard let centralManager = centralManager else {
            print("❌ Cannot connect - CBCentralManager not initialized")
            return
        }
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnect(from device: BluetoothDevice) {
        print("🔌 Disconnecting from \(device.displayName)")
        guard let centralManager = centralManager else {
            print("❌ Cannot disconnect - CBCentralManager not initialized")
            return
        }
        centralManager.cancelPeripheralConnection(device.peripheral)
    }
    
    func checkPermission() -> Bool {
        guard let centralManager = centralManager else { return false }
        let isAvailable = centralManager.state == .poweredOn
        print("📱 Bluetooth permission check: \(isAvailable ? "✅ Available" : "❌ Not Available")")
        return isAvailable
    }
    
    func requestPermission() {
        print("📱 Requesting Bluetooth permission...")
        if centralManager == nil {
            setupCentralManager()
        }
    }
}

// MARK: - DataTransmissionProtocol Conformance
extension BluetoothConnectionManager: DataTransmissionProtocol {
    func sendData(_ data: Data) {
        sendData(data) { result in
            switch result {
            case .success:
                print("✅ Data sent successfully")
            case .failure(let error):
                print("❌ Failed to send data: \(error.localizedDescription)")
            }
        }
    }
    
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let connectedPeripheral = connectedPeripheral else {
            completion(.failure(BluetoothError.noConnectedDevice))
            return
        }
        
        guard let fff2Characteristic = fff2Characteristic else {
            completion(.failure(BluetoothError.characteristicNotFound))
            return
        }
        
        guard fff2Characteristic.properties.contains(.write) else {
            completion(.failure(BluetoothError.characteristicNotWritable))
            return
        }
        
        connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
        print("📤 Data sent: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        completion(.success(()))
    }
}

// MARK: - ConnectionQualityProtocol Conformance
extension BluetoothConnectionManager: ConnectionQualityProtocol {
    typealias QualityMetric = NSNumber
    
    func startQualityMonitoring() {
        guard let peripheral = connectedPeripheral else { return }
        
        // Read RSSI immediately
        peripheral.readRSSI()
        
        // Set up timer to read RSSI periodically
        qualityMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if self.connectedPeripheral != nil && self.connectedDevices.contains(peripheral.identifier) {
                peripheral.readRSSI()
            }
        }
    }
    
    func stopQualityMonitoring() {
        qualityMonitoringTimer?.invalidate()
        qualityMonitoringTimer = nil
        qualityMetric = nil
    }
}

// MARK: - Private Methods
private extension BluetoothConnectionManager {
    func setupCentralManager() {
        print("🔧 Setting up CBCentralManager...")
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        
        centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
        
        // Set up initialization timeout
        setupInitializationTimeout()
    }
    
    func setupInitializationTimeout() {
        initializationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if self.connectionState == .unknown {
                print("⚠️ CBCentralManager delegate method never called, forcing re-initialization...")
                self.forceBluetoothInitialization()
            }
        }
    }
    
    func forceBluetoothInitialization() {
        print("🔄 Force re-initializing CBCentralManager...")
        centralManager = nil
        setupCentralManager()
    }
    
    func handleBluetoothNotReady() {
        switch connectionState {
        case .unknown:
            print("⏳ Waiting for Bluetooth initialization...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.connectionState.isReady {
                    self.startScanning()
                }
            }
        case .poweredOff:
            print("💡 Please turn on Bluetooth in Settings > Bluetooth")
        case .unauthorized:
            print("💡 Please grant Bluetooth permission in Settings")
        default:
            print("⚠️ Bluetooth not available: \(connectionState.description)")
        }
    }
    
    func cleanup() {
        initializationTimer?.invalidate()
        stopQualityMonitoring()
        stopScanning()
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothConnectionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("🔔 CBCentralManager state updated: \(central.state.rawValue)")
        
        initializationTimer?.invalidate()
        initializationTimer = nil
        
        DispatchQueue.main.async {
            self.connectionState = BluetoothConnectionState(from: central.state)
            
            if self.connectionState.isReady && self.availableDevices.isEmpty {
                print("🔄 Auto-starting scan since Bluetooth became ready")
                self.startScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name,
              name.lowercased().hasPrefix(openterfaceDevicePrefix) else {
            return
        }
        
        print("📱 Discovered device: \(name)")
        
        DispatchQueue.main.async {
            let device = BluetoothDevice(peripheral: peripheral, rssi: RSSI)
            if !self.availableDevices.contains(device) {
                peripheral.delegate = self
                self.availableDevices.append(device)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral
        connectedDevices.insert(peripheral.identifier)
        peripheral.discoverServices(nil)
        
        startQualityMonitoring()
        
        DispatchQueue.main.async {
            self.showPopupBinding?.wrappedValue = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("🔌 Disconnected from \(peripheral.name ?? "Unknown")")
        connectedDevices.remove(peripheral.identifier)
        
        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            fff2Characteristic = nil
            stopQualityMonitoring()
        }
        
        if let error = error {
            print("❌ Disconnection error: \(error.localizedDescription)")
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothConnectionManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("❌ No services found")
            return
        }
        
        for service in services {
            print("📋 Service UUID: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("❌ No characteristics found for service \(service.uuid)")
            return
        }
        
        for characteristic in characteristics {
            print("📋 Characteristic UUID: \(characteristic.uuid)")
            
            if characteristic.uuid == fff2CharacteristicUUID {
                fff2Characteristic = characteristic
                print("✅ FFF2 characteristic found!")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            print("❌ Error reading RSSI: \(error.localizedDescription)")
            return
        }
        
        DispatchQueue.main.async {
            self.qualityMetric = RSSI
        }
    }
}

// MARK: - Custom Errors
enum BluetoothError: LocalizedError {
    case noConnectedDevice
    case characteristicNotFound
    case characteristicNotWritable
    
    var errorDescription: String? {
        switch self {
        case .noConnectedDevice:
            return "No connected device available"
        case .characteristicNotFound:
            return "Required characteristic not found"
        case .characteristicNotWritable:
            return "Characteristic does not support writing"
        }
    }
}
