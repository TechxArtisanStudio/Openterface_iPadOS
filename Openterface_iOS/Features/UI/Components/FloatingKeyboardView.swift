//
//  FloatingKeyboardView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI

struct FloatingKeyboardView: View {
    @Binding var isPresented: Bool
    @ObservedObject var keyboardManager: KeyboardInputManager
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    // Mac keyboard layout
    private let keyRows: [[String]] = [
        ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Del"],
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Cmd", "Space", "Cmd", "Alt", "Ctrl"]
    ]
    
    var body: some View {
        ZStack {
            // Floating keyboard panel (no background overlay to allow mouse interaction)
            keyboardContainer
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .offset(dragOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(true) // Allow hit testing for the keyboard itself
        .background(
            // Semi-transparent background that doesn't block interactions
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(false) // This allows touches to pass through to the underlying view
        )
    }
    
    // MARK: - Keyboard Container
    private var keyboardContainer: some View {
        VStack(spacing: 0) {
            // Header with drag handle and controls
            keyboardHeaderView
            
            // Keyboard rows
            keyboardRowsView
        }
        .frame(width: keyboardWidth + 32) // Add padding equivalent (16 points on each side)
    }
    
    // MARK: - Header View
    private var keyboardHeaderView: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Virtual Keyboard")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Mouse still active")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Mode indicator
            Text(keyboardManager.currentMode.description)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(4)
            
            // Close button
            Button(action: {
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            // Add a more opaque background to make the keyboard clearly visible
            Color.backgroundPrimary
                .opacity(0.95)
                .background(.ultraThinMaterial)
        )
        .gesture(dragGesture)
    }
    
    // MARK: - Keyboard Rows View
    private var keyboardRowsView: some View {
        VStack(spacing: 4) {
            ForEach(Array(keyRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { key in
                        KeyButton(
                            key: key,
                            displayValue: getDisplayValue(for: key),
                            width: keyWidth(for: key, in: rowIndex),
                            isPressed: keyboardManager.pressedKeys.contains(key),
                            isModifier: isModifierKey(key),
                            isModifierActive: isModifierActive(key),
                            onPress: {
                                // Add haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                if self.isModifierKey(key) {
                                    self.handleKeyPress(key)
                                } else {
                                    self.keyboardManager.handleKeyPress(key)
                                }
                            },
                            onRelease: {
                                if !self.isModifierKey(key) {
                                    self.keyboardManager.handleKeyRelease(key)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            // Add a more opaque background to make the keyboard clearly visible
            Color.backgroundSecondary
                .opacity(0.95)
                .background(.ultraThinMaterial)
        )
    }
    
    // MARK: - Computed Properties
    private var keyboardWidth: CGFloat {
        let rowWidths = keyRows.enumerated().map { rowIndex, row in
            let keyWidths = row.map { keyWidth(for: $0, in: rowIndex) }
            let spacing = CGFloat(row.count - 1) * 2
            return keyWidths.reduce(0, +) + spacing
        }
        return rowWidths.max() ?? 400
    }
    
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                withAnimation(.none) {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                isDragging = false
                constrainToScreen()
            }
    }
    
    // MARK: - Helper Methods
    private func keyWidth(for key: String, in row: Int) -> CGFloat {
        switch key {
        case "Space": return 180
        case "Shift": return row == 4 ? 80 : 60
        case "Backspace", "Enter": return 80
        case "Tab", "Caps": return 70
        case "Ctrl", "Alt", "Cmd", "Del": return 50
        case "\\": return 60
        default: return 40
        }
    }
    
    private func getDisplayValue(for key: String) -> String {
        let specialKeys = ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Del",
                          "Tab", "Caps", "Enter", "Shift", "Ctrl", "Alt", "Cmd", "Space", "Backspace", "\\"]
        
        if specialKeys.contains(key) {
            return key.keyDisplayName
        }
        
        let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
        let isCapsActive = keyboardManager.capsLockActive
        
        // For letters
        if key.count == 1 && key.first!.isLetter {
            let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
            return shouldBeUppercase ? key.uppercased() : key.lowercased()
        }
        
        // For numbers and symbols with shift variants
        if isShiftActive {
            let shiftMap: [String: String] = [
                "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
                "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
                "-": "_", "=": "+", "[": "{", "]": "}",
                ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"
            ]
            return shiftMap[key] ?? key
        }
        
        return key
    }
    
    private func isModifierKey(_ key: String) -> Bool {
        return key.isModifierKey
    }
    
    private func isModifierActive(_ key: String) -> Bool {
        if key == "Caps" {
            return keyboardManager.capsLockActive
        }
        return keyboardManager.activeModifiers.contains(key)
    }
    
    private func handleKeyPress(_ key: String) {
        if isModifierKey(key) {
            if key == "Caps" {
                keyboardManager.handleKeyPress(key)
            } else {
                keyboardManager.handleModifierToggle(key)
            }
        }
        // For regular keys, handleKeyPress is called directly in onPress
    }
    
    private func constrainToScreen() {
        let screenSize = UIScreen.main.bounds.size
        let keyboardSize = CGSize(width: keyboardWidth + 40, height: 300)
        
        let maxX = (screenSize.width - keyboardSize.width) / 2
        let maxY = (screenSize.height - keyboardSize.height) / 2
        
        let constrainedX = max(-maxX, min(maxX, dragOffset.width))
        let constrainedY = max(-maxY, min(maxY, dragOffset.height))
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = CGSize(width: constrainedX, height: constrainedY)
        }
    }
}

// MARK: - Key Button
struct KeyButton: View {
    let key: String
    let displayValue: String
    let width: CGFloat
    let isPressed: Bool
    let isModifier: Bool
    let isModifierActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    @State private var isButtonPressed = false
    
    private var keyHeight: CGFloat { 36 }
    
    private var fontSize: CGFloat {
        switch key {
        case "Space": return 12
        case "Backspace", "Enter", "Shift", "Tab", "Caps", "Del": return 10
        case "Ctrl", "Alt", "Cmd": return 9
        default: return 14
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(buttonColor)
                .frame(width: width, height: keyHeight)
            
            Text(displayValue)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(buttonTextColor)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isButtonPressed {
                        isButtonPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    if isButtonPressed {
                        isButtonPressed = false
                        onRelease()
                    }
                }
        )
    }
    
    private var buttonColor: Color {
        if isButtonPressed || isPressed {
            return isModifier ? (isModifierActive ? Color.blue.opacity(0.8) : Color.gray.opacity(0.6)) : Color.blue.opacity(0.6)
        } else {
            return isModifier ? (isModifierActive ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2)) : Color.gray.opacity(0.1)
        }
    }
    
    private var buttonTextColor: Color {
        if isButtonPressed || isPressed {
            return .white
        } else {
            return .primary
        }
    }
}

#Preview {
    FloatingKeyboardView(
        isPresented: .constant(true),
        keyboardManager: KeyboardInputManager(connectionManager: BluetoothConnectionManager())
    )
}
