//
//  KeyboardInputManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import Combine

final class KeyboardInputManager: ObservableObject {
    // MARK: - Published Properties
    @Published var activeModifiers: Set<String> = []
    @Published var capsLockActive: Bool = false
    @Published var pressedKeys: Set<String> = []
    @Published var currentMode: KeyboardMode = .normal
    
    // MARK: - Dependencies
    private let connectionManager: any ConnectionProtocol
    private var compositeKeyManager: CompositeKeyInputManager?
    
    // MARK: - Constants
    private let keyboardCodes: [String: UInt8] = [
        // Letters (uppercase)
        "A": 0x04, "B": 0x05, "C": 0x06, "D": 0x07, "E": 0x08, "F": 0x09,
        "G": 0x0A, "H": 0x0B, "I": 0x0C, "J": 0x0D, "K": 0x0E, "L": 0x0F,
        "M": 0x10, "N": 0x11, "O": 0x12, "P": 0x13, "Q": 0x14, "R": 0x15,
        "S": 0x16, "T": 0x17, "U": 0x18, "V": 0x19, "W": 0x1A, "X": 0x1B,
        "Y": 0x1C, "Z": 0x1D,
        
        // Letters (lowercase) - same codes as uppercase
        "a": 0x04, "b": 0x05, "c": 0x06, "d": 0x07, "e": 0x08, "f": 0x09,
        "g": 0x0A, "h": 0x0B, "i": 0x0C, "j": 0x0D, "k": 0x0E, "l": 0x0F,
        "m": 0x10, "n": 0x11, "o": 0x12, "p": 0x13, "q": 0x14, "r": 0x15,
        "s": 0x16, "t": 0x17, "u": 0x18, "v": 0x19, "w": 0x1A, "x": 0x1B,
        "y": 0x1C, "z": 0x1D,
        
        // Numbers
        "1": 0x1E, "2": 0x1F, "3": 0x20, "4": 0x21, "5": 0x22,
        "6": 0x23, "7": 0x24, "8": 0x25, "9": 0x26, "0": 0x27,
        
        // Special characters
        "Enter": 0x28, "Escape": 0x29, "Backspace": 0x2A, "Tab": 0x2B,
        "Space": 0x2C, "-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30,
        "\\": 0x31, ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36,
        ".": 0x37, "/": 0x38, "Caps": 0x39,
        
        // Function keys
        "F1": 0x3A, "F2": 0x3B, "F3": 0x3C, "F4": 0x3D, "F5": 0x3E, "F6": 0x3F,
        "F7": 0x40, "F8": 0x41, "F9": 0x42, "F10": 0x43, "F11": 0x44, "F12": 0x45,
        
        // Additional keys
        "Delete": 0x4C, "Insert": 0x49, "Home": 0x4A, "End": 0x4D,
        "PageUp": 0x4B, "PageDown": 0x4E,
        "PgUp": 0x4B, "PgDn": 0x4E,
        
        // Arrow keys
        "Right": 0x4F, "Left": 0x50, "Down": 0x51, "Up": 0x52,
        
        // Numpad keys
        "Numpad0": 0x62, "Numpad1": 0x59, "Numpad2": 0x5A, "Numpad3": 0x5B,
        "Numpad4": 0x5C, "Numpad5": 0x5D, "Numpad6": 0x5E, "Numpad7": 0x5F,
        "Numpad8": 0x60, "Numpad9": 0x61, "NumpadDot": 0x63, "NumpadSlash": 0x54,
        "NumpadAsterisk": 0x55, "NumpadMinus": 0x56, "NumpadPlus": 0x57,
        "NumpadEnter": 0x58, "NumpadEquals": 0x67, "NumLock": 0x53,
        
        // Modifier keys
        "Ctrl": 0xE0, "Shift": 0xE1, "Alt": 0xE2, "Cmd": 0xE3,
        
        // Aliases
        "Esc": 0x29, "Del": 0x4C
    ]
    
    private let modifierMasks: [String: UInt8] = [
        "Ctrl": 0x01,   // Left Control
        "Shift": 0x02,  // Left Shift
        "Alt": 0x04,    // Left Alt
        "Cmd": 0x08     // Left GUI (Command)
    ]
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
    }
    
    // MARK: - Configuration
    func setCompositeKeyManager(_ manager: CompositeKeyInputManager) {
        self.compositeKeyManager = manager
    }
    
    // MARK: - Mode Management
    func switchMode(to mode: KeyboardMode) {
        currentMode = mode
        print("🎮 Switched to \(mode.description) mode")
    }
    
    var isGameMode: Bool {
        return currentMode == .game
    }
}

// MARK: - KeyboardInputProtocol Conformance
extension KeyboardInputManager: KeyboardInputProtocol {
    func handleInput<T>(_ input: T) {
        if let keyEvent = input as? String {
            handleKeyPress(keyEvent)
        }
    }
    
    func handleKeyPress(_ key: String) {
        print("⌨️ Key pressed: \(key)")
        
        // Handle modifier keys
        if modifierMasks.keys.contains(key) {
            handleModifierToggle(key)
            return
        }
        
        // Handle Caps Lock
        if key == "Caps" {
            capsLockActive.toggle()
            print("🔒 Caps Lock: \(capsLockActive ? "ON" : "OFF")")
            sendCapsLockState()
            return
        }
        
        // Handle regular keys
        let keyAlias = mapKeyAlias(key)
        
        guard let keyCode = keyboardCodes[keyAlias] else {
            print("❌ Unknown key: \(key)")
            return
        }
        
        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Apply caps lock effect for letters
        if keyAlias.count == 1 && keyAlias.first!.isLetter {
            let shouldBeUppercase = capsLockActive != activeModifiers.contains("Shift")
            if shouldBeUppercase {
                modifierByte |= modifierMasks["Shift"] ?? 0x00
            }
        }
        
        // Send key press
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)
        
        // Send key release after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            var releaseModifierByte: UInt8 = 0x00
            for modifier in self.activeModifiers {
                if let modifierMask = self.modifierMasks[modifier] {
                    releaseModifierByte |= modifierMask
                }
            }
            self.sendKeyboardData(modifier: releaseModifierByte, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }
    
    func handleKeyRelease(_ key: String) {
        let keyAlias = mapKeyAlias(key)
        pressedKeys.remove(keyAlias)
        
        // Build current state without the released key
        var modifierByte: UInt8 = 0x00
        var keyCodesToSend: [UInt8] = []
        
        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Add remaining pressed keys
        for pressedKey in pressedKeys {
            if let keyCode = keyboardCodes[pressedKey], keyCodesToSend.count < 6 {
                keyCodesToSend.append(keyCode)
            }
        }
        
        // Pad key codes array to 6 elements
        while keyCodesToSend.count < 6 {
            keyCodesToSend.append(0x00)
        }
        
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodesToSend)
    }
    
    func handleModifierToggle(_ modifier: String) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
            print("🔓 \(modifier) released")
        } else {
            activeModifiers.insert(modifier)
            print("🔒 \(modifier) pressed")
        }
        
        // Send current modifier state
        var modifierByte: UInt8 = 0x00
        for activeModifier in activeModifiers {
            if let modifierMask = modifierMasks[activeModifier] {
                modifierByte |= modifierMask
            }
        }
        
        sendKeyboardData(modifier: modifierByte, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
    
    func handleKeyCombo(modifiers: [String], key: String) {
        print("🔗 Key combo: \(modifiers.joined(separator: "+"))+\(key)")
        
        guard let keyCode = keyboardCodes[key] else {
            print("❌ Unknown key in combo: \(key)")
            return
        }
        
        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        // Apply modifiers
        for modifier in modifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Send key combo press
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)
        
        // Send key release after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }
    
    func handleTextInput(_ text: String) {
        for (index, char) in text.enumerated() {
            let key = String(char).uppercased()
            
            // Check if we need shift for uppercase or special characters
            let needsShift = char.isUppercase || "!@#$%^&*()_+{}|:\"<>?".contains(char)
            
            if needsShift && !activeModifiers.contains("Shift") {
                handleModifierToggle("Shift")
            } else if !needsShift && activeModifiers.contains("Shift") {
                handleModifierToggle("Shift")
            }
            
            // Add delay between characters
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                self.handleKeyPress(key)
            }
        }
    }
}

// MARK: - Private Methods
private extension KeyboardInputManager {
    func sendCapsLockState() {
        let capsKeyCode = keyboardCodes["Caps"] ?? 0x39
        let keyCodes: [UInt8] = [capsKeyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        sendKeyboardData(modifier: 0x00, keyCodes: keyCodes)
        
        // Release caps lock key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }
    
    func sendKeyboardData(modifier: UInt8, keyCodes: [UInt8]) {
        // HID keyboard report format:
        // [Report ID, Modifier, Reserved, Key1, Key2, Key3, Key4, Key5, Key6]
        var dataPacket: [UInt8] = currentMode.dataPacketHeader
        dataPacket.append(modifier)
        dataPacket.append(0x00) // Reserved byte
        dataPacket.append(contentsOf: keyCodes)
        
        // Calculate checksum
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }
    
    func mapKeyAlias(_ key: String) -> String {
        switch key {
        case "↑": return "Up"
        case "↓": return "Down"
        case "←": return "Left"
        case "→": return "Right"
        case "PgUp": return "PageUp"
        case "PgDn": return "PageDown"
        case "Home", "home": return "Home"
        case "End", "end": return "End"
        case "Esc": return "Escape"
        case "Del": return "Delete"
        default: return key
        }
    }
}

// MARK: - Public API
extension KeyboardInputManager {
    func getCurrentModeDescription() -> String {
        return currentMode.description
    }
    
    func handleSpecialKey(_ key: String) {
        switch key {
        case "Esc":
            handleKeyPress("Escape")
        case "Caps":
            handleKeyPress("Caps")
        default:
            handleKeyPress(key)
        }
    }
}
