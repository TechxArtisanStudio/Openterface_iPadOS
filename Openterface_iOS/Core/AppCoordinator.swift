//
//  AppCoordinator.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation

/// Main application coordinator that manages all feature managers
final class AppCoordinator: ObservableObject {
    // MARK: - Feature Managers
    @Published var bluetoothManager: BluetoothConnectionManager
    @Published var cameraManager: CameraSessionManager
    @Published var keyboardManager: KeyboardInputManager
    @Published var mouseManager: MouseInputManager
    
    // MARK: - UI State
    @Published var showBLEPopup = false
    @Published var showFloatingKeyboard = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        // Initialize managers in correct order
        let bluetoothConnectionManager = BluetoothConnectionManager()
        self.bluetoothManager = bluetoothConnectionManager
        self.cameraManager = CameraSessionManager()
        self.keyboardManager = KeyboardInputManager(connectionManager: bluetoothConnectionManager)
        self.mouseManager = MouseInputManager(connectionManager: bluetoothConnectionManager)
        
        // Initialize composite key manager
        let compositeKeyManager = CompositeKeyInputManager()
        compositeKeyManager.setKeyboardManager(keyboardManager)
        keyboardManager.setCompositeKeyManager(compositeKeyManager)
        
        setupBindings()
        setupInitialConfiguration()
    }
    
    // MARK: - Setup Methods
    private func setupBindings() {
        // Bind BLE popup to Bluetooth manager
        bluetoothManager.showPopupBinding = Binding(
            get: { self.showBLEPopup },
            set: { self.showBLEPopup = $0 }
        )
        
        // Setup any additional bindings between managers
        setupCrossManagerBindings()
    }
    
    private func setupCrossManagerBindings() {
        // Example: React to Bluetooth connection changes
        bluetoothManager.$connectedDevices
            .sink { [weak self] connectedDevices in
                if !connectedDevices.isEmpty {
                    print("🔗 Bluetooth connected, enabling input managers")
                    // Could enable/disable input managers based on connection
                }
            }
            .store(in: &cancellables)
        
        // Example: React to camera authorization changes
        cameraManager.$isAuthorized
            .sink { [weak self] isAuthorized in
                if isAuthorized {
                    print("📹 Camera authorized in AppCoordinator")
                    // Camera manager will auto-start the session
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupInitialConfiguration() {
        // Keep screen always on during usage
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start initial services
        startInitialServices()
    }
    
    private func startInitialServices() {
        // Check and request permissions
        print("🚀 AppCoordinator startInitialServices - checking camera authorization")
        
        // Add detailed camera auth test
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("🚀 Raw camera auth status in AppCoordinator: \(status)")
        print("🚀 Camera isAuthorized before check: \(cameraManager.isAuthorized)")
        
        cameraManager.checkCameraAuthorization()
        
        print("🚀 Camera isAuthorized after check: \(cameraManager.isAuthorized)")
        print("🚀 AppCoordinator startInitialServices - checking audio authorization")
        cameraManager.checkAudioAuthorization()
        
        // Initialize Bluetooth with delay to ensure proper setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.bluetoothManager.checkPermission() {
                self.bluetoothManager.startScanning()
            } else {
                print("📱 Bluetooth permission not granted, requesting permission...")
                self.bluetoothManager.requestPermission()
                
                // Check again after requesting permission
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if self.bluetoothManager.checkPermission() {
                        self.bluetoothManager.startScanning()
                    } else {
                        print("📱 User needs to manually grant Bluetooth permission in Settings")
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Show BLE connection popup
    func showBluetoothConnection() {
        showBLEPopup = true
    }
    
    /// Show floating keyboard
    func showKeyboard() {
        showFloatingKeyboard = true
    }
    
    /// Hide floating keyboard
    func hideKeyboard() {
        showFloatingKeyboard = false
    }
    
    /// Toggle floating keyboard visibility
    func toggleKeyboard() {
        showFloatingKeyboard.toggle()
    }
    
    /// Request camera access
    func requestCameraAccess() {
        cameraManager.requestCameraAccess()
    }
    
    /// Request audio access
    func requestAudioAccess() {
        cameraManager.requestAudioAccess()
    }
    
    /// Switch keyboard mode
    func switchKeyboardMode(to mode: KeyboardMode) {
        keyboardManager.switchMode(to: mode)
    }
    
    /// Toggle audio monitoring
    func toggleAudioMonitoring() {
        cameraManager.toggleAudioMonitoring()
    }
    
    /// Force refresh authorization status
    func forceRefreshAuthorization() {
        cameraManager.forceRefreshAuthorization()
    }
    
    /// Get RSSI icon based on signal strength
    func getRSSIIcon() -> String {
        guard let rssi = bluetoothManager.qualityMetric?.intValue else {
            return "wifi.slash"
        }
        
        switch rssi {
        case -30...0:
            return "wifi"
        case -50...(-30):
            return "wifi"
        case -70...(-50):
            return "wifi"
        default:
            return "wifi.exclamationmark"
        }
    }
    
    /// Get RSSI color based on signal strength
    func getRSSIColor() -> Color {
        guard let rssi = bluetoothManager.qualityMetric?.intValue else {
            return .gray
        }
        
        switch rssi {
        case -30...0:
            return .green
        case -50...(-30):
            return .yellow
        case -70...(-50):
            return .orange
        default:
            return .red
        }
    }
    
    /// Reset discovery flags
    func resetDeviceDiscoveryFlags() {
        cameraManager.resetDiscoveryFlags()
    }
    
    /// Force camera session start for debugging
    func debugStartCameraSession() {
        print("🐛 Debug: Forcing camera session start")
        print("Camera authorized: \(cameraManager.isAuthorized)")
        print("Camera selected: \(cameraManager.selectedCamera?.localizedName ?? "None")")
        print("Session state: \(cameraManager.sessionState)")
        print("Session available: \(cameraManager.captureSession != nil)")
        
        if cameraManager.isAuthorized && cameraManager.selectedCamera != nil {
            cameraManager.startSession()
        }
    }
}

// MARK: - Cleanup
extension AppCoordinator {
    /// Clean up resources when app goes to background or terminates
    func cleanup() {
        // Re-enable idle timer
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Stop services
        bluetoothManager.stopScanning()
        cameraManager.stopSession()
        
        // Cancel subscriptions
        cancellables.removeAll()
    }
}

// MARK: - Development Helpers
#if DEBUG
extension AppCoordinator {
    /// Debug method to print current state
    func printDebugState() {
        print("=== App State Debug ===")
        print("Bluetooth State: \(bluetoothManager.connectionState.description)")
        print("Connected Devices: \(bluetoothManager.connectedDevices.count)")
        print("Camera Authorized: \(cameraManager.isAuthorized)")
        print("Audio Authorized: \(cameraManager.isAudioAuthorized)")
        print("Camera Session: \(cameraManager.sessionState.description)")
        print("Keyboard Mode: \(keyboardManager.currentMode.description)")
        print("Active Modifiers: \(keyboardManager.activeModifiers)")
        print("Mouse Select Mode: \(mouseManager.isSelectMode)")
        print("=====================")
    }
}
#endif
