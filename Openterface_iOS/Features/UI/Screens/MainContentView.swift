//
//  MainContentView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI

struct MainContentView: View {
    @StateObject private var appCoordinator = AppCoordinator()
    
    var body: some View {
        VStack(spacing: 0) {
            // Debug print for authorization status
            let _ = print("🖥️ MainContentView body - isAuthorized: \(appCoordinator.cameraManager.isAuthorized)")
            let _ = print("🖥️ MainContentView body - cameraManager object: \(appCoordinator.cameraManager)")
            
            if appCoordinator.cameraManager.isAuthorized {
                // Camera preview takes full width and most of the screen
                ZStack {
                    CameraPreviewView(
                        cameraManager: appCoordinator.cameraManager,
                        mouseManager: appCoordinator.mouseManager
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        print("📱 CameraPreviewView appeared in MainContentView")
                        print("🖥️ Camera authorized: \(appCoordinator.cameraManager.isAuthorized)")
                        print("🖥️ Session state: \(appCoordinator.cameraManager.sessionState)")
                        print("🖥️ Session available: \(appCoordinator.cameraManager.captureSession != nil)")
                    }
                    
                    // Show loading indicator when camera is starting
                    if appCoordinator.cameraManager.sessionState == .starting {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Starting Camera...")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.top, 8)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                    }
                    
                    // Show error message if camera fails
                    if case .error(let error) = appCoordinator.cameraManager.sessionState {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundColor(.red)
                            Text("Camera Error")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                    }
                }
                
                // Controls at the bottom
                ControlsView(appCoordinator: appCoordinator)
                
            } else {
                // Permission request view
                PermissionRequestView(appCoordinator: appCoordinator)
                    .onAppear {
                        print("❌ Camera not authorized - showing PermissionRequestView")
                    }
            }
        }
        .onAppear {
            print("📱 MainContentView appeared")
            // App lifecycle handled in AppCoordinator
        }
        .onDisappear {
            print("📱 MainContentView disappeared")
            appCoordinator.cleanup()
        }
        .sheet(isPresented: $appCoordinator.showBLEPopup) {
            BluetoothConnectionView(bluetoothManager: appCoordinator.bluetoothManager)
        }
        .overlay {
            // Floating Virtual Keyboard
            if appCoordinator.showFloatingKeyboard {
                FloatingKeyboardView(
                    isPresented: $appCoordinator.showFloatingKeyboard,
                    keyboardManager: appCoordinator.keyboardManager
                )
                .animation(.spring(response: 0.3), value: appCoordinator.showFloatingKeyboard)
            }
        }
    }
}

// MARK: - Controls View
struct ControlsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            // BLE Connection Status and Controls
            BluetoothStatusView(appCoordinator: appCoordinator)
            
            // Camera and Audio Info
            if appCoordinator.cameraManager.currentDeviceName != nil {
                CameraAudioInfoView(appCoordinator: appCoordinator)
            }
            
            // Debug button for camera
            #if DEBUG
            VStack(spacing: 8) {
                HStack {
                    Button("Debug Camera") {
                        appCoordinator.debugStartCameraSession()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    Button("Print State") {
                        appCoordinator.printDebugState()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                
                HStack {
                    Button("Check Auth") {
                        print("🔍 Manual auth check triggered")
                        appCoordinator.cameraManager.checkCameraAuthorization()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    Button("Force Refresh") {
                        print("🔄 Force refresh triggered")
                        appCoordinator.forceRefreshAuthorization()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            #endif
        }
        .padding()
        .background(Color.backgroundPrimary)
    }
}

// MARK: - Bluetooth Status View
struct BluetoothStatusView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(appCoordinator.bluetoothManager.connectedDevices.isEmpty ? .gray : .primaryAccent)
                
                Text("BLE: \(connectionStatusText)")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                // BLE RSSI indicator
                if let rssi = appCoordinator.bluetoothManager.qualityMetric {
                    HStack(spacing: 4) {
                        Image(systemName: appCoordinator.getRSSIIcon())
                            .font(.caption2)
                            .foregroundColor(appCoordinator.getRSSIColor())
                        Text("\(rssi.intValue) dBm")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Button(action: {
                    appCoordinator.showBluetoothConnection()
                }) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundColor(.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    appCoordinator.showKeyboard()
                }) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundColor(.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var connectionStatusText: String {
        let connectedCount = appCoordinator.bluetoothManager.connectedDevices.count
        return connectedCount == 0 ? "Disconnected" : "\(connectedCount) Connected"
    }
}

// MARK: - Camera Audio Info View
struct CameraAudioInfoView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 8) {
            // Video device info
            HStack {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundColor(.primaryAccent)
                Text("Video: \(appCoordinator.cameraManager.currentDeviceName ?? "Unknown")")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                // New camera indicator
                if appCoordinator.cameraManager.hasNewCameraDetected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("New")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Audio device info
            HStack {
                Image(systemName: audioIconName)
                    .font(.caption)
                    .foregroundColor(audioIconColor)
                
                Text(audioStatusText)
                    .font(.caption)
                    .foregroundColor(audioTextColor)
                
                Spacer()
                
                // Audio monitoring toggle
                if appCoordinator.cameraManager.isAudioAuthorized {
                    Button(action: {
                        appCoordinator.toggleAudioMonitoring()
                    }) {
                        Image(systemName: audioMonitoringIcon)
                            .font(.caption)
                            .foregroundColor(audioMonitoringColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // New audio device indicator
                if appCoordinator.cameraManager.hasNewAudioDeviceDetected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("New")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
    
    private var audioIconName: String {
        return appCoordinator.cameraManager.isAudioAuthorized ? "mic.fill" : "mic.slash.fill"
    }
    
    private var audioIconColor: Color {
        return appCoordinator.cameraManager.isAudioAuthorized ? .green : .red
    }
    
    private var audioStatusText: String {
        if let audioDeviceName = appCoordinator.cameraManager.currentAudioDeviceName {
            return "Audio: \(audioDeviceName)"
        } else {
            return appCoordinator.cameraManager.isAudioAuthorized ? "Audio: Searching..." : "Audio: No Access"
        }
    }
    
    private var audioTextColor: Color {
        if appCoordinator.cameraManager.currentAudioDeviceName != nil {
            return .gray
        } else {
            return appCoordinator.cameraManager.isAudioAuthorized ? .orange : .red
        }
    }
    
    private var audioMonitoringIcon: String {
        return appCoordinator.cameraManager.isAudioMonitoringEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }
    
    private var audioMonitoringColor: Color {
        return appCoordinator.cameraManager.isAudioMonitoringEnabled ? .primaryAccent : .gray
    }
}

// MARK: - Permission Request View
struct PermissionRequestView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Please allow camera and microphone access to use Openterface")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                Button("Grant Camera Access") {
                    appCoordinator.requestCameraAccess()
                }
                .buttonStyle(.borderedProminent)
                
                if !appCoordinator.cameraManager.isAudioAuthorized {
                    Button("Grant Audio Access") {
                        appCoordinator.requestAudioAccess()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }
}

#Preview {
    MainContentView()
}
