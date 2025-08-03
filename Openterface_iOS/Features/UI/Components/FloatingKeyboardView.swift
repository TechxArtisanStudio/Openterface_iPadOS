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
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // Floating keyboard panel
            VStack(spacing: 0) {
                // Header with drag handle and controls
                keyboardHeaderView
                
                // Keyboard rows
                keyboardRowsView
            }
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
            .offset(dragOffset)
        }
    }
    
    // MARK: - Header View
    private var keyboardHeaderView: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("Virtual Keyboard")
                .font(.headline)
                .foregroundColor(.primary)
            
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
        .frame(width: keyboardWidth)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.backgroundPrimary)
        .cornerRadius(8)
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
                            action: {
                                handleKeyPress(key)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
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
        } else {
            keyboardManager.handleKeyPress(key)
        }
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
    let action: () -> Void
    
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
        Button(action: {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            action()
        }) {
            Text(displayValue)
                .font(.system(size: fontSize, weight: .medium))
                .frame(width: width, height: keyHeight)
        }
        .keyboardButtonStyle(
            isPressed: isButtonPressed || isPressed,
            isModifier: isModifier,
            isActive: isModifierActive
        )
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.05)) {
                isButtonPressed = pressing
            }
        }, perform: {})
    }
}

#Preview {
    FloatingKeyboardView(
        isPresented: .constant(true),
        keyboardManager: KeyboardInputManager(connectionManager: BluetoothConnectionManager())
    )
}
