//
//  ControlsView.swift
//  Openterface_iOS
//
//  Created by Refactor on 10/17/25.
//

import SwiftUI

// MARK: - Controls View
struct ControlsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @ObservedObject private var bluetoothManager: BluetoothConnectionManager
    @AppStorage("AIIntegrationEnabled") private var isAIEnabled = false
    
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
        self.bluetoothManager = appCoordinator.bluetoothManager
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Single row: All control buttons
            HStack(spacing: 12) {
                // 1. BLE Connectivity Button
                ControlButton(
                    customIcon: BluetoothLogoView(
                        color: bleIconColor ?? .gray,
                        size: 18
                    )
                    .frame(width: 18, height: 18),
                    label: "BLE",
                    action: {
                        appCoordinator.showBluetoothConnection()
                    },
                    bottomIndicatorColor: bleIndicatorColor,
                    iconColor: bleIconColor,
                    rssiText: bleRssiText,
                    fixedWidth: 60
                )
                
                // 2. Video Settings Button
                Menu {
                    Button(action: { appCoordinator.cameraManager.setSessionPreset(.hd1920x1080) }) {
                        HStack {
                            Text("1080p")
                            if appCoordinator.cameraManager.currentResolution == "1080p" {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button(action: { appCoordinator.cameraManager.setSessionPreset(.hd1280x720) }) {
                        HStack {
                            Text("720p")
                            if appCoordinator.cameraManager.currentResolution == "720p" {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primaryAccent)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.clear)
                            )
                        Text(appCoordinator.cameraManager.currentResolution)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .frame(width: nil)
                }
                
                // 3. Audio Control Button
                ControlButton(
                    icon: appCoordinator.cameraManager.isAudioMonitoringEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    label: "Audio",
                    action: {
                        if appCoordinator.cameraManager.isAudioAuthorized {
                            appCoordinator.toggleAudioMonitoring()
                        } else {
                            appCoordinator.requestAudioAccess()
                        }
                    },
                    isActive: appCoordinator.cameraManager.isAudioMonitoringEnabled
                )

                // 4. Record Video Button
                ControlButton(
                    icon: "record.circle.fill",
                    label: "Record",
                    action: {
                        appCoordinator.toggleVideoRecording()
                    },
                    isActive: appCoordinator.isRecording
                )

                // 5. Screenshot Button
                ControlButton(
                    icon: "camera.fill",
                    label: "Screenshot",
                    action: {
                        appCoordinator.captureScreenshot()
                    }
                )

                // 6. Virtual Keyboard Button
                ControlButton(
                    icon: "keyboard.fill",
                    label: "Keyboard",
                    action: {
                        appCoordinator.showFloatingKeyboard.toggle()
                    },
                    isActive: appCoordinator.showFloatingKeyboard
                )

                // 6.3. Target OS Button (cycles: Win -> Mac -> Linux)
                TargetOSButton(
                    targetOS: appCoordinator.targetOS,
                    action: {
                        appCoordinator.cycleTargetOS()
                    }
                )

                // 6.5. Macro Button
                ControlButton(
                    icon: "keyboard.badge.ellipsis",
                    label: "Macro",
                    action: {
                        appCoordinator.toggleMacroPanel()
                    }
                )

                // 6.6. AI Chat Button (only shown when AI integration is enabled)
                if isAIEnabled {
                    ControlButton(
                        icon: "message.fill",
                        label: "AI",
                        action: {
                            appCoordinator.toggleChatPanel()
                        }
                    )
                }

                // 7. Zoom Mode Button
                ControlButton(
                    icon: "magnifyingglass.circle.fill",
                    label: "Zoom",
                    action: {
                        appCoordinator.isZoomMode.toggle()
                        // Reset viewport to center when toggling zoom mode
                        appCoordinator.cameraManager.resetViewport()
                    },
                    isActive: appCoordinator.isZoomMode
                )

                // 7.5. Mouse Mode Button (Pan/iPencil)
                ControlButton(
                    icon: appCoordinator.isPencilMode ? "pencil.tip" : "hand.draw.fill",
                    label: appCoordinator.isPencilMode ? "iPencil" : "Pan",
                    action: {
                        appCoordinator.toggleMouseMode()
                    },
                    isActive: appCoordinator.isPencilMode
                )

                // 7.6. Fullscreen Button
                ControlButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    label: "Fullscreen",
                    action: {
                        appCoordinator.isFullScreen.toggle()
                    },
                    isActive: appCoordinator.isFullScreen
                )

                // 8. Rotate Button
                ControlButton(
                    icon: "rotate.right",
                    label: "Rotate",
                    action: {
                        appCoordinator.cameraManager.cycleOrientationCorrection()
                    }
                )

                // 8.5. Info Button
                ControlButton(
                    icon: "info.circle.fill",
                    label: "Info",
                    action: {
                        appCoordinator.showInfoOverlay.toggle()
                    },
                    isActive: appCoordinator.showInfoOverlay
                )
                
                Spacer()

                // 9. Settings Button
                ControlButton(
                    icon: "gearshape.fill",
                    label: "Settings",
                    action: {
                        appCoordinator.showSettings.toggle()
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)
        }
    }
}

// MARK: - Computed Properties
private extension ControlsView {
    var bleIndicatorColor: Color? {
        guard !bluetoothManager.connectedDevices.isEmpty,
              let rssi = bluetoothManager.qualityMetric else { return nil }
        let value = rssi.intValue
        switch value {
        case -50...0: return .green
        case -70..<(-50): return .orange
        default: return .red
        }
    }
    
    var bleIconColor: Color? {
        return bluetoothManager.connectedDevices.isEmpty ? nil : .green
    }
    
    var bleRssiText: String? {
        guard !bluetoothManager.connectedDevices.isEmpty,
              let rssi = bluetoothManager.qualityMetric else { return nil }
        return "\(rssi.intValue) dBm"
    }
}

// MARK: - Control Button Component
struct ControlButton<Icon: View>: View {
    let icon: String?
    let customIcon: Icon?
    let label: String
    let action: () -> Void
    var isActive: Bool = false
    var bottomIndicatorColor: Color? = nil
    var iconColor: Color? = nil
    var rssiText: String? = nil
    var fixedWidth: CGFloat? = nil
    
    init(icon: String, label: String, action: @escaping () -> Void, isActive: Bool = false, bottomIndicatorColor: Color? = nil, iconColor: Color? = nil, rssiText: String? = nil, fixedWidth: CGFloat? = nil) where Icon == EmptyView {
        self.icon = icon
        self.customIcon = nil
        self.label = label
        self.action = action
        self.isActive = isActive
        self.bottomIndicatorColor = bottomIndicatorColor
        self.iconColor = iconColor
        self.rssiText = rssiText
        self.fixedWidth = fixedWidth
    }
    
    init(customIcon: Icon, label: String, action: @escaping () -> Void, isActive: Bool = false, bottomIndicatorColor: Color? = nil, iconColor: Color? = nil, rssiText: String? = nil, fixedWidth: CGFloat? = nil) {
        self.icon = nil
        self.customIcon = customIcon
        self.label = label
        self.action = action
        self.isActive = isActive
        self.bottomIndicatorColor = bottomIndicatorColor
        self.iconColor = iconColor
        self.rssiText = rssiText
        self.fixedWidth = fixedWidth
    }
    
    private var fullLabel: String {
        rssiText ?? label
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                if let customIcon = customIcon {
                    customIcon
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor ?? (isActive ? .primaryAccent : .gray))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isActive ? Color.primaryAccent.opacity(0.1) : Color.clear)
                        )
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor ?? (isActive ? .primaryAccent : .gray))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isActive ? Color.primaryAccent.opacity(0.1) : Color.clear)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if let color = bottomIndicatorColor {
                Rectangle()
                    .fill(color)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
            
            Text(fullLabel)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(width: fixedWidth)
    }
}

#Preview {
    ControlsView(appCoordinator: AppCoordinator())
}

// MARK: - Target OS Button
struct TargetOSButton: View {
    let targetOS: MacroTargetSystem
    let action: () -> Void

    private var displayLabel: String {
        switch targetOS {
        case .macOS: return "Mac"
        case .windows: return "Win"
        case .linux: return "Linux"
        case .iOS: return "iOS"
        case .android: return "Android"
        }
    }

    private var displayIcon: String {
        switch targetOS {
        case .macOS: return "applelogo"
        case .windows: return "pc"
        case .linux: return "terminal"
        case .iOS: return "iphone"
        case .android: return "phone.fill"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: displayIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primaryAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.primaryAccent.opacity(0.1))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Text(displayLabel)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}
