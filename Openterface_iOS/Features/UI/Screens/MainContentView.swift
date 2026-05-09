//
//  MainContentView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI
import AVFoundation

struct MainContentView: View {
    @StateObject private var appCoordinator = AppCoordinator()
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Debug print for authorization status
                let _ = print("🖥️ MainContentView body - isAuthorized: \(appCoordinator.cameraManager.isAuthorized)")
                let _ = print("🖥️ MainContentView body - cameraManager object: \(appCoordinator.cameraManager)")
                
                if appCoordinator.cameraManager.isAuthorized {
                // Camera preview takes full width and most of the screen
                ZStack {
                    CameraPreviewView(
                        cameraManager: appCoordinator.cameraManager,
                        mouseManager: appCoordinator.mouseManager,
                        appCoordinator: appCoordinator
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(appCoordinator.isFullScreen ? .all : [])
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
                    
                    // Zoom indicator (top-right corner)
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                // Zoom indicator
                                if appCoordinator.cameraManager.currentZoomFactor > 1.0 {
                                    VStack(spacing: 4) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                        Text("\(String(format: "%.1f", appCoordinator.cameraManager.currentZoomFactor))x")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(20)
                                    .transition(.opacity.combined(with: .scale))
                                }
                                
                                // Pan hint when zoomed
                                if appCoordinator.cameraManager.currentZoomFactor > 1.0 {
                                    VStack(spacing: 2) {
                                        Image(systemName: "hand.draw")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text("3 fingers to pan")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.4))
                                    .cornerRadius(12)
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                        }
                        .padding(.top, 60) // Account for safe area
                        .padding(.trailing, 16)
                        Spacer()
                    }
                    .animation(.easeInOut(duration: 0.2), value: appCoordinator.cameraManager.currentZoomFactor)
                }
                
                // Controls at the bottom (hidden in fullscreen mode)
                if !appCoordinator.isFullScreen {
                    ControlsView(appCoordinator: appCoordinator)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
            } else {
                // Permission request view
                PermissionRequestView(appCoordinator: appCoordinator)
                    .onAppear {
                        print("❌ Camera not authorized - showing PermissionRequestView")
                    }
            }
        }
        
        // Exit fullscreen button - overlaid on top of all layers (top-left corner)
        if appCoordinator.isFullScreen {
            VStack {
                HStack {
                    Button(action: {
                        withAnimation {
                            appCoordinator.isFullScreen = false
                        }
                    }) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .opacity(0.7)
                    .padding(.top, 5)
                    .padding(.leading, 16)
                    Spacer()
                }
                Spacer()
            }
        }
    }
    // .animation(.easeInOut(duration: 0.3), value: appCoordinator.isFullScreen)
    .statusBar(hidden: appCoordinator.isFullScreen)
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
        .sheet(isPresented: $appCoordinator.showMacroPanel) {
            MacroPanelView(
                macroManager: appCoordinator.macroManager,
                defaultFilter: appCoordinator.targetOS
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $appCoordinator.showChatPanel) {
            ChatView(
                chatManager: appCoordinator.chatManager,
                authService: appCoordinator.githubAuthService,
                appCoordinator: appCoordinator,
                showLoginSheet: $appCoordinator.showLoginSheet
            )
        }
        .sheet(isPresented: $appCoordinator.showLoginSheet) {
            LoginView(authService: appCoordinator.githubAuthService)
        }
        .sheet(isPresented: $appCoordinator.showSettings) {
            SettingsView(appCoordinator: appCoordinator)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            
            // Info Overlay (top-right corner)
            if appCoordinator.showInfoOverlay {
                VStack {
                    HStack {
                        Spacer()
                        InfoOverlayView(appCoordinator: appCoordinator)
                    }
                    Spacer()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: appCoordinator.showInfoOverlay)
            }
        }
        .background {
            // External Bluetooth Keyboard Handler
            ExternalKeyboardHandlerView(keyboardManager: appCoordinator.keyboardManager)
                .frame(width: 0, height: 0) // Invisible but functional
                .allowsHitTesting(false) // Don't interfere with other touch interactions
        }
    }
}

// MARK: - Bluetooth Status View
struct BluetoothStatusView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @ObservedObject var bluetoothManager: BluetoothConnectionManager
    
    var body: some View {
        VStack(spacing: 8) {
            // BLE Connection row - Compact version with icon, RSSI, and status
            HStack(spacing: 8) {
                // BLE Settings Button (Left)
                Button(action: {
                    appCoordinator.showBluetoothConnection()
                }) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundColor(.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                
                // RSSI Indicator
                if let rssi = bluetoothManager.qualityMetric {
                    HStack(spacing: 2) {
                        Image(systemName: appCoordinator.getRSSIIcon())
                            .font(.caption2)
                            .foregroundColor(appCoordinator.getRSSIColor())
                        Text("\(rssi.intValue) dBm")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    appCoordinator.showKeyboard()
                }) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundColor(.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Audio monitoring row
            HStack {
                // Audio monitoring toggle on the left
                Button(action: {
                    if appCoordinator.cameraManager.isAudioAuthorized {
                        appCoordinator.toggleAudioMonitoring()
                    } else {
                        appCoordinator.requestAudioAccess()
                    }
                }) {
                    Image(systemName: audioMonitoringIcon)
                        .font(.caption)
                        .foregroundColor(audioMonitoringColor)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
        }
    }
    
    private var audioMonitoringIcon: String {
        if !appCoordinator.cameraManager.isAudioAuthorized {
            return "speaker.slash.fill"
        }
        return appCoordinator.cameraManager.isAudioMonitoringEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }
    
    private var audioMonitoringColor: Color {
        if !appCoordinator.cameraManager.isAudioAuthorized {
            return .red
        }
        return appCoordinator.cameraManager.isAudioMonitoringEnabled ? .green : .gray
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
