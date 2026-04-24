//
//  InfoOverlayView.swift
//  Openterface_iOS
//
//  Created by GitHub Copilot on 10/23/25.
//

import SwiftUI

/// Info overlay that displays current mouse and keyboard status
struct InfoOverlayView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @ObservedObject var mouseManager: MouseInputManager
    @ObservedObject var keyboardManager: KeyboardInputManager
    
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
        self.mouseManager = appCoordinator.mouseManager
        self.keyboardManager = appCoordinator.keyboardManager
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            // Container with semi-transparent background
            VStack(alignment: .leading, spacing: 12) {
                // Title
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Text("Input Status")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                Divider()
                    .background(Color.gray.opacity(0.4))
                
                // Mouse Information Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "computermouse.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Text("Mouse")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    
                    InfoRow(label: "Mode", value: mouseMode)
                    
                    if let position = mouseManager.currentPosition {
                        InfoRow(label: "Position", value: String(format: "%.1f, %.1f", position.x, position.y))
                    } else {
                        InfoRow(label: "Position", value: "N/A")
                    }
                    
                    InfoRow(label: "Drag Mode", value: mouseManager.isSelectMode ? "Active" : "Inactive")
                    InfoRow(label: "Scrolling", value: mouseManager.isTwoFingerScrolling ? "Active" : "Inactive")
                }
                
                Divider()
                    .background(Color.gray.opacity(0.4))
                
                // Keyboard Information Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Text("Keyboard")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    
                    InfoRow(label: "Mode", value: keyboardMode)
                    InfoRow(label: "Caps Lock", value: keyboardManager.capsLockActive ? "ON" : "OFF")
                    
                    if !keyboardManager.activeModifiers.isEmpty {
                        InfoRow(label: "Modifiers", value: Array(keyboardManager.activeModifiers).joined(separator: ", "))
                    } else {
                        InfoRow(label: "Modifiers", value: "None")
                    }
                    
                    if !keyboardManager.pressedKeys.isEmpty {
                        let keysText = Array(keyboardManager.pressedKeys).prefix(5).joined(separator: ", ")
                        let suffix = keyboardManager.pressedKeys.count > 5 ? "..." : ""
                        InfoRow(label: "Keys", value: keysText + suffix)
                    } else {
                        InfoRow(label: "Keys", value: "None")
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .background(.ultraThinMaterial.opacity(0.6))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
            )
            .frame(maxWidth: 280)
        }
        .padding(16)
        .allowsHitTesting(false) // Make overlay transparent to touches
    }
    
    // MARK: - Computed Properties
    
    private var mouseMode: String {
        if appCoordinator.isPencilMode {
            return "Absolute (iPencil)"
        } else {
            return "Relative (Pan)"
        }
    }
    
    private var keyboardMode: String {
        return keyboardManager.currentMode.rawValue
    }
}

// MARK: - Info Row Component
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption2)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.caption2)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        
        InfoOverlayView(appCoordinator: AppCoordinator())
    }
}
