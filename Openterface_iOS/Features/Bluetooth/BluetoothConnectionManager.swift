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
    @Published var qualityMetric: NSNumber? = nil {
        didSet {
            // logDebug("qualityMetric didSet: \(qualityMetric?.intValue ?? 0) dBm", category: .bluetooth)
        }
    }
    @Published var rssiValue: Int = 0 // Helper for easier UI binding
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var connectingPeripheral: CBPeripheral? // Keep reference during connection
    private var fff2Characteristic: CBCharacteristic?
    private var initializationTimer: Timer?
    private var qualityMonitoringTimer: Timer?
    private var autoConnectTimer: Timer?
    private var keepAliveTimer: Timer?
    
    // MARK: - Auto-Connection Configuration
    @Published var autoConnectEnabled: Bool = true
    private let autoConnectDelay: TimeInterval = 2.0 // Wait 2 seconds for additional devices
    private let startupAutoConnectTimeout: TimeInterval = 5.0 // Wait 5 seconds for startup auto-connect
    private let keepAliveInterval: TimeInterval = 10.0 // Send keep-alive every 10 seconds (reduced from 30)
    private let connectionTimeoutInterval: TimeInterval = 15.0 // Monitor connection timeout
    private var startupAutoConnectAttempted = false
    private var startupAutoConnectTimer: Timer?
    private var lastConnectionWasAuto = false
    private var connectionTimeoutTimer: Timer?
    private var lastDataSentTime: Date?
    
    // MARK: - Reconnection Configuration
    private var reconnectionAttempts = 0
    private let maxReconnectionAttempts = 3
    private var reconnectionTimer: Timer?
    private let reconnectionDelay: TimeInterval = 2.0 // Wait 2 seconds between reconnection attempts
    private var lastConnectedPeripheral: CBPeripheral?
    
    // MARK: - UI Binding
    var showPopupBinding: Binding<Bool>?
    
    // MARK: - Constants
    private let openterfaceDevicePrefix = "kvm"
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
        logInfo("Starting BLE scanning...", category: .bluetooth)
        availableDevices.removeAll()
        
        // Reset auto-connection timer
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        
        // Start startup auto-connect timer if not attempted
        if !startupAutoConnectAttempted {
            startupAutoConnectTimer?.invalidate()
            startupAutoConnectTimer = Timer.scheduledTimer(withTimeInterval: startupAutoConnectTimeout, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.attemptStartupAutoConnect()
                }
            }
        }
        
        guard let centralManager = centralManager else {
            logError("Cannot start scanning - CBCentralManager not initialized", category: .bluetooth)
            return
        }
        
        guard connectionState.isReady else {
            logError("Cannot start scanning - Bluetooth state: \(connectionState.description)", category: .bluetooth)
            handleBluetoothNotReady()
            return
        }
        
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logInfo("BLE scanning started successfully", category: .bluetooth)
    }
    
    func stopScanning() {
        logInfo("Stopping BLE scanning...", category: .bluetooth)
        centralManager?.stopScan()
    }
    
    func connect(to device: BluetoothDevice) {
        logInfo("Connecting to \(device.displayName)", category: .bluetooth)
        
        // Cancel auto-connection timer since user is manually connecting
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        
        lastConnectionWasAuto = false
        
        guard let centralManager = centralManager else {
            logError("Cannot connect - CBCentralManager not initialized", category: .bluetooth)
            return
        }
        
        // Store peripheral reference BEFORE connecting to prevent deallocation
        connectingPeripheral = device.peripheral
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnect(from device: BluetoothDevice) {
        logInfo("Disconnecting from \(device.displayName)", category: .bluetooth)
        guard let centralManager = centralManager else {
            logError("Cannot disconnect - CBCentralManager not initialized", category: .bluetooth)
            return
        }
        centralManager.cancelPeripheralConnection(device.peripheral)
    }
    
    func checkPermission() -> Bool {
        guard let centralManager = centralManager else { return false }
        let isAvailable = centralManager.state == .poweredOn
        logDebug("Bluetooth permission check: \(isAvailable ? "Available" : "Not Available")", category: .bluetooth)
        return isAvailable
    }
    
    func requestPermission() {
        logInfo("Requesting Bluetooth permission...", category: .bluetooth)
        if centralManager == nil {
            setupCentralManager()
        }
    }
    
    func setAutoConnectEnabled(_ enabled: Bool) {
        autoConnectEnabled = enabled
        if !enabled {
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
            startupAutoConnectTimer?.invalidate()
            startupAutoConnectTimer = nil
        }
        logInfo("Auto-connection \(enabled ? "enabled" : "disabled")", category: .bluetooth)
    }
}

// MARK: - DataTransmissionProtocol Conformance
extension BluetoothConnectionManager: DataTransmissionProtocol {
    func sendData(_ data: Data) {
        sendData(data) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                logError("Failed to send data: \(error.localizedDescription)", category: .bluetooth)
            }
        }
    }
    
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let connectedPeripheral = connectedPeripheral else {
            logError("Cannot send data - no connected device", category: .bluetooth)
            completion(.failure(BluetoothError.noConnectedDevice))
            return
        }
        
        guard let fff2Characteristic = fff2Characteristic else {
            logError("Cannot send data - FFF2 characteristic not found", category: .bluetooth)
            completion(.failure(BluetoothError.characteristicNotFound))
            return
        }
        
        guard fff2Characteristic.properties.contains(.write) else {
            logError("Cannot send data - FFF2 characteristic not writable", category: .bluetooth)
            completion(.failure(BluetoothError.characteristicNotWritable))
            return
        }
        
        logDebug("Sending data to \(connectedPeripheral.name ?? "Unknown"): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))", category: .bluetooth)
        connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
        
        // Track the data transmission time for keep-alive purposes
        lastDataSentTime = Date()
        
        completion(.success(()))
    }
}

// MARK: - ConnectionQualityProtocol Conformance
extension BluetoothConnectionManager: ConnectionQualityProtocol {
    typealias QualityMetric = NSNumber
    
    func startQualityMonitoring() {
        guard let peripheral = connectedPeripheral else {
            logWarning("Quality monitoring requested but no peripheral connected", category: .bluetooth)
            return
        }
        
        logInfo("Starting quality monitoring for \(peripheral.name ?? "Unknown")", category: .bluetooth)
        
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
        rssiValue = 0
    }
    
    func startKeepAlive() {
        keepAliveTimer?.invalidate()
        lastDataSentTime = Date()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { _ in
            self.sendKeepAlive()
        }
        logDebug("Keep-alive started with \(self.keepAliveInterval)s interval", category: .bluetooth)
    }
    
    func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        lastDataSentTime = nil
    }
    
    private func sendKeepAlive() {
        guard let peripheral = connectedPeripheral else {
            logWarning("Keep-alive attempted but no peripheral connected", category: .bluetooth)
            return
        }
        
        // Send a more robust keep-alive packet
        // Using a valid mouse report format with explicit zeros
        let keepAliveData = Data([0x00, 0x00, 0x00, 0x00])
        
        logDebug("Sending keep-alive packet to \(peripheral.name ?? "Unknown")", category: .bluetooth)
        
        sendData(keepAliveData) { result in
            switch result {
            case .success:
                self.lastDataSentTime = Date()
                logDebug("Keep-alive packet sent successfully", category: .bluetooth)
            case .failure(let error):
                logError("Failed to send keep-alive packet: \(error.localizedDescription)", category: .bluetooth)
                // Consider this a connection quality issue
            }
        }
    }
}

// MARK: - Private Methods
private extension BluetoothConnectionManager {
    func setupCentralManager() {
        logDebug("Setting up CBCentralManager...", category: .bluetooth)
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
                logWarning("CBCentralManager delegate method never called, forcing re-initialization...", category: .bluetooth)
                self.forceBluetoothInitialization()
            }
        }
    }
    
    func forceBluetoothInitialization() {
        logInfo("Force re-initializing CBCentralManager...", category: .bluetooth)
        centralManager = nil
        setupCentralManager()
    }
    
    func handleBluetoothNotReady() {
        switch connectionState {
        case .unknown:
            logInfo("Waiting for Bluetooth initialization...", category: .bluetooth)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.connectionState.isReady {
                    self.startScanning()
                }
            }
        case .poweredOff:
            logWarning("Please turn on Bluetooth in Settings > Bluetooth", category: .bluetooth)
        case .unauthorized:
            logWarning("Please grant Bluetooth permission in Settings", category: .bluetooth)
        default:
            logWarning("Bluetooth not available: \(connectionState.description)", category: .bluetooth)
        }
    }
    
    func cleanup() {
        initializationTimer?.invalidate()
        autoConnectTimer?.invalidate()
        startupAutoConnectTimer?.invalidate()
        reconnectionTimer?.invalidate()
        stopQualityMonitoring()
        stopKeepAlive()
        stopScanning()
    }
    
    func checkForAutoConnection() {
        guard autoConnectEnabled else { return }
        guard connectedDevices.isEmpty else { return } // Don't auto-connect if already connected
        
        // Cancel any existing auto-connect timer
        autoConnectTimer?.invalidate()
        
        if availableDevices.count >= 1 {
            // Start timer to wait for additional devices or better signals
            logDebug("Auto-connection: Found \(availableDevices.count) device(s), waiting \(autoConnectDelay)s for more...", category: .bluetooth)
            autoConnectTimer = Timer.scheduledTimer(withTimeInterval: autoConnectDelay, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.performAutoConnection()
                }
            }
        }
    }
    
    func performAutoConnection() {
        guard autoConnectEnabled else { return }
        guard connectedDevices.isEmpty else { return }
        guard !availableDevices.isEmpty else { return }
        
        // Find device with best RSSI (highest value, since RSSI is negative, less negative is better)
        let bestDevice = availableDevices.max(by: { $0.rssi.intValue < $1.rssi.intValue })
        
        if let device = bestDevice {
            logInfo("Auto-connecting to best device: \(device.displayName) (RSSI: \(device.rssi))", category: .bluetooth)
            lastConnectionWasAuto = true
            connect(to: device)
            stopScanning() // Stop scanning once we auto-connect
        } else {
            logWarning("No valid device found for auto-connect", category: .bluetooth)
        }
    }
    
    func attemptStartupAutoConnect() {
        guard !startupAutoConnectAttempted else { return }
        startupAutoConnectAttempted = true
        
        guard autoConnectEnabled else {
            logDebug("Startup auto-connect disabled", category: .bluetooth)
            return
        }
        
        guard connectedDevices.isEmpty else {
            logDebug("Already connected, skipping startup auto-connect", category: .bluetooth)
            return
        }
        
        guard !availableDevices.isEmpty else {
            logDebug("No devices found during startup scan, disabling auto-connect", category: .bluetooth)
            setAutoConnectEnabled(false)
            return
        }
        
        // Find device with best RSSI (highest value, since RSSI is negative, less negative is better)
        let bestDevice = availableDevices.max(by: { $0.rssi.intValue < $1.rssi.intValue })
        
        if let device = bestDevice {
            logInfo("Startup auto-connecting to best device: \(device.displayName) (RSSI: \(device.rssi))", category: .bluetooth)
            lastConnectionWasAuto = true
            connect(to: device)
            stopScanning()
        } else {
            logWarning("No valid device found for startup auto-connect", category: .bluetooth)
            setAutoConnectEnabled(false)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothConnectionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logDebug("CBCentralManager state updated: \(central.state.rawValue)", category: .bluetooth)
        
        initializationTimer?.invalidate()
        initializationTimer = nil
        
        DispatchQueue.main.async {
            self.connectionState = BluetoothConnectionState(from: central.state)
            
            if self.connectionState.isReady && self.availableDevices.isEmpty {
                logInfo("Auto-starting scan since Bluetooth became ready", category: .bluetooth)
                self.startScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name,
              name.lowercased().hasPrefix(openterfaceDevicePrefix) else {
            return
        }
        
        logInfo("Discovered device: \(name)", category: .bluetooth)
        
        DispatchQueue.main.async {
            let device = BluetoothDevice(peripheral: peripheral, rssi: RSSI)
            if !self.availableDevices.contains(device) {
                peripheral.delegate = self
                self.availableDevices.append(device)
                
                // Check for auto-connection
                self.checkForAutoConnection()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logInfo("Connected to \(peripheral.name ?? "Unknown")", category: .bluetooth)
        connectedPeripheral = peripheral
        connectingPeripheral = nil // Clear connecting reference
        lastConnectedPeripheral = peripheral // Store for reconnection
        connectedDevices.insert(peripheral.identifier)
        peripheral.discoverServices(nil)
        
        // Reset reconnection counter on successful connection
        reconnectionAttempts = 0
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        
        // Start quality monitoring and keep-alive
        startQualityMonitoring()
        startKeepAlive()
        lastDataSentTime = Date() // Track when connection was established
        
        DispatchQueue.main.async {
            self.showPopupBinding?.wrappedValue = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logInfo("Disconnected from \(peripheral.name ?? "Unknown")", category: .bluetooth)
        connectedDevices.remove(peripheral.identifier)
        
        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            connectingPeripheral = nil // Also clear connecting reference
            fff2Characteristic = nil
            stopQualityMonitoring()
            stopKeepAlive()
        }
        
        if let error = error {
            logError("Disconnection error: \(error.localizedDescription)", category: .bluetooth)
            
            // Check if it's a timeout error
            let nsError = error as NSError
            if nsError.code == 6 || error.localizedDescription.contains("timed out") {
                logWarning("Connection timeout detected, attempting reconnection...", category: .bluetooth)
                attemptReconnection(to: peripheral)
                return
            }
        }
        
        // If last connection was auto and auto-connect is enabled, restart scanning
        if lastConnectionWasAuto && autoConnectEnabled && !availableDevices.isEmpty {
            logInfo("Auto-reconnecting after disconnection...", category: .bluetooth)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Wait 1 second before restarting
                self.startScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logError("Failed to connect to \(peripheral.name ?? "Unknown")", category: .bluetooth)
        if let error = error {
            logError("Connection error: \(error.localizedDescription)", category: .bluetooth)
        }
        
        // Clear connecting reference on failure
        connectingPeripheral = nil
        
        // If we were in a reconnection attempt, continue trying
        if reconnectionAttempts > 0 && reconnectionAttempts < maxReconnectionAttempts {
            logWarning("Connection attempt failed, will retry...", category: .bluetooth)
            attemptReconnection(to: peripheral)
            return
        }
        
        // If startup auto-connect failed, disable auto-connect
        if startupAutoConnectAttempted && connectedDevices.isEmpty {
            logWarning("Startup auto-connect failed, disabling auto-connect", category: .bluetooth)
            setAutoConnectEnabled(false)
        }
        
        // Reset reconnection counter if we've exhausted attempts
        if reconnectionAttempts >= maxReconnectionAttempts {
            reconnectionAttempts = 0
        }
    }
    
    func attemptReconnection(to peripheral: CBPeripheral) {
        guard reconnectionAttempts < maxReconnectionAttempts else {
            logError("Max reconnection attempts (\(maxReconnectionAttempts)) reached. Giving up.", category: .bluetooth)
            reconnectionAttempts = 0
            
            // Fall back to scanning if auto-connect was enabled
            if lastConnectionWasAuto && autoConnectEnabled {
                logInfo("Falling back to device scanning...", category: .bluetooth)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startScanning()
                }
            }
            return
        }
        
        reconnectionAttempts += 1
        logInfo("Reconnection attempt \(reconnectionAttempts) of \(maxReconnectionAttempts) to \(peripheral.name ?? "Unknown")...", category: .bluetooth)
        
        // Cancel any existing reconnection timer
        reconnectionTimer?.invalidate()
        
        // Schedule reconnection attempt
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: reconnectionDelay, repeats: false) { _ in
            DispatchQueue.main.async {
                guard let centralManager = self.centralManager else {
                    logError("Cannot reconnect - CBCentralManager not initialized", category: .bluetooth)
                    return
                }
                
                // Store peripheral reference BEFORE reconnecting to prevent deallocation
                self.connectingPeripheral = peripheral
                
                // Attempt to reconnect
                logDebug("Executing reconnection attempt \(self.reconnectionAttempts)...", category: .bluetooth)
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothConnectionManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logError("Error discovering services: \(error.localizedDescription)", category: .bluetooth)
            return
        }
        
        guard let services = peripheral.services else {
            logWarning("No services found", category: .bluetooth)
            return
        }
        
        for service in services {
            logDebug("Service UUID: \(service.uuid)", category: .bluetooth)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logError("Error discovering characteristics: \(error.localizedDescription)", category: .bluetooth)
            return
        }
        
        guard let characteristics = service.characteristics else {
            logWarning("No characteristics found for service \(service.uuid)", category: .bluetooth)
            return
        }
        
        logDebug("Discovered \(characteristics.count) characteristic(s) for service \(service.uuid)", category: .bluetooth)
        
        for characteristic in characteristics {
            logDebug("Characteristic UUID: \(characteristic.uuid)", category: .bluetooth)
            
            if characteristic.uuid == fff2CharacteristicUUID {
                fff2Characteristic = characteristic
                logInfo("FFF2 characteristic found! Starting quality monitoring...", category: .bluetooth)
                DispatchQueue.main.async {
                    self.startQualityMonitoring()
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            logError("Error reading RSSI: \(error.localizedDescription)", category: .bluetooth)
            return
        }
        
        DispatchQueue.main.async {
            let rssiInt = RSSI.intValue
            self.qualityMetric = RSSI
            self.rssiValue = rssiInt
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
