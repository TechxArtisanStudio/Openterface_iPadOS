//
//  HIDUtils.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation

/// Utility functions for HID (Human Interface Device) operations
enum HIDUtils {
    
    // MARK: - Keyboard HID Codes
    
    /// Map key names to HID usage codes
    static func getKeyCode(for key: String) -> UInt8? {
        return KeyboardHIDCodes.codes[key]
    }
    
    /// Map modifier names to HID modifier masks
    static func getModifierMask(for modifier: String) -> UInt8? {
        return KeyboardHIDCodes.modifierMasks[modifier]
    }
    
    /// Create HID keyboard report
    static func createKeyboardReport(
        mode: KeyboardMode,
        modifier: UInt8,
        keyCodes: [UInt8]
    ) -> Data {
        var dataPacket = mode.dataPacketHeader
        dataPacket.append(modifier)
        dataPacket.append(0x00) // Reserved byte
        dataPacket.append(contentsOf: keyCodes)
        
        // Calculate checksum
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        
        return Data(dataPacket)
    }
    
    // MARK: - Mouse HID Codes
    
    /// Get mouse button code
    static func getMouseButtonCode(for button: MouseButton) -> UInt8 {
        switch button {
        case .left: return 0x01
        case .right: return 0x02
        case .middle: return 0x04
        }
    }
    
    /// Create mouse movement report
    static func createMouseMoveReport(dx: Int8, dy: Int8) -> Data {
        return Data([0x00, 0x00, UInt8(bitPattern: dx), UInt8(bitPattern: dy)])
    }
    
    /// Create mouse click report
    static func createMouseClickReport(button: MouseButton, pressed: Bool) -> Data {
        let buttonCode = pressed ? getMouseButtonCode(for: button) : 0x00
        return Data([buttonCode, 0x00, 0x00, 0x00])
    }
    
    /// Create mouse scroll report
    static func createMouseScrollReport(dx: Int8, dy: Int8) -> Data {
        return Data([0x00, 0x00, UInt8(bitPattern: dx), UInt8(bitPattern: dy)])
    }
}

// MARK: - Keyboard HID Codes
private enum KeyboardHIDCodes {
    static let codes: [String: UInt8] = [
        // Letters (case-insensitive)
        "A": 0x04, "B": 0x05, "C": 0x06, "D": 0x07, "E": 0x08, "F": 0x09,
        "G": 0x0A, "H": 0x0B, "I": 0x0C, "J": 0x0D, "K": 0x0E, "L": 0x0F,
        "M": 0x10, "N": 0x11, "O": 0x12, "P": 0x13, "Q": 0x14, "R": 0x15,
        "S": 0x16, "T": 0x17, "U": 0x18, "V": 0x19, "W": 0x1A, "X": 0x1B,
        "Y": 0x1C, "Z": 0x1D,
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
        
        // Navigation keys
        "Delete": 0x4C, "Insert": 0x49, "Home": 0x4A, "End": 0x4D,
        "PageUp": 0x4B, "PageDown": 0x4E, "Right": 0x4F, "Left": 0x50,
        "Down": 0x51, "Up": 0x52,
        
        // Numpad keys
        "Numpad0": 0x62, "Numpad1": 0x59, "Numpad2": 0x5A, "Numpad3": 0x5B,
        "Numpad4": 0x5C, "Numpad5": 0x5D, "Numpad6": 0x5E, "Numpad7": 0x5F,
        "Numpad8": 0x60, "Numpad9": 0x61, "NumpadDot": 0x63, "NumpadSlash": 0x54,
        "NumpadAsterisk": 0x55, "NumpadMinus": 0x56, "NumpadPlus": 0x57,
        "NumpadEnter": 0x58, "NumpadEquals": 0x67, "NumLock": 0x53,
        
        // Modifier keys
        "Ctrl": 0xE0, "Shift": 0xE1, "Alt": 0xE2, "Cmd": 0xE3,
        
        // Aliases
        "Esc": 0x29, "Del": 0x4C, "PgUp": 0x4B, "PgDn": 0x4E
    ]
    
    static let modifierMasks: [String: UInt8] = [
        "Ctrl": 0x01,   // Left Control
        "Shift": 0x02,  // Left Shift
        "Alt": 0x04,    // Left Alt
        "Cmd": 0x08     // Left GUI (Command)
    ]
}
