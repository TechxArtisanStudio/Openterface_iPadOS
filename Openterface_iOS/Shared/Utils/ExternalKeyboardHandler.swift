//
//  ExternalKeyboardHandler.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import UIKit
import SwiftUI

/// Handles external hardware keyboard input for iOS devices
class ExternalKeyboardHandler: UIView {
    
    // MARK: - Properties
    weak var keyboardManager: KeyboardInputManager?
    private var pressedKeysTracker: Set<String> = []
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeyboardHandler()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyboardHandler()
    }
    
    // MARK: - Setup
    private func setupKeyboardHandler() {
        // Make this view capable of becoming first responder
        isUserInteractionEnabled = true
        
        // Add key commands for hardware keyboard
        setupKeyCommands()
    }
    
    // MARK: - First Responder
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        print("🎮 ExternalKeyboardHandler becoming first responder")
        keyboardManager?.setExternalKeyboardMode(true)
        return super.becomeFirstResponder()
    }
    
    override func resignFirstResponder() -> Bool {
        print("🎮 ExternalKeyboardHandler resigning first responder")
        keyboardManager?.setExternalKeyboardMode(false)
        return super.resignFirstResponder()
    }
    
    // MARK: - Key Commands Setup
    private func setupKeyCommands() {
        // We'll add key commands dynamically since we need to handle all possible keys
        // This will be handled in the pressesBegan/pressesEnded methods
    }
    
    // MARK: - Key Event Handling
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        
        for press in presses {
            if let key = press.key {
                let keyString = mapUIKeyToString(key)
                print("🎮 External keyboard key pressed: \(keyString)")
                
                // Track pressed keys to avoid duplicates
                if !pressedKeysTracker.contains(keyString) {
                    pressedKeysTracker.insert(keyString)
                    
                    // Handle modifier keys differently
                    if isModifierKey(keyString) {
                        keyboardManager?.handleModifierPress(keyString)
                    } else {
                        keyboardManager?.handleKeyPress(keyString)
                    }
                    handled = true
                }
            }
        }
        
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        
        for press in presses {
            if let key = press.key {
                let keyString = mapUIKeyToString(key)
                print("🎮 External keyboard key released: \(keyString)")
                
                // Remove from tracked keys and send release event
                if pressedKeysTracker.contains(keyString) {
                    pressedKeysTracker.remove(keyString)
                    
                    // Handle modifier keys differently
                    if isModifierKey(keyString) {
                        keyboardManager?.handleModifierRelease(keyString)
                    } else {
                        keyboardManager?.handleKeyRelease(keyString)
                    }
                    handled = true
                }
            }
        }
        
        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }
    
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Handle cancelled presses the same as ended presses
        pressesEnded(presses, with: event)
    }
    
    // MARK: - Key Mapping
    private func mapUIKeyToString(_ key: UIKey) -> String {
        // First check for modifier key usage codes
        let modifierKey = mapModifierKeyCode(key.keyCode)
        if modifierKey != "Unknown" {
            return modifierKey
        }
        
        // Handle regular keys by characters first
        let characters = key.charactersIgnoringModifiers
        if !characters.isEmpty {
            let char = characters
            
            // Handle special cases first
            switch char {
            case " ": return "Space"
            case "\t": return "Tab"
            case "\r", "\n": return "Enter"
            case "\u{7F}": return "Backspace"
            case "\u{08}": return "Backspace"  // Alternative backspace character
            case "\u{1B}": return "Escape"
            default:
                // Handle regular characters
                if char.count == 1 {
                    let firstChar = char.first!
                    if firstChar.isLetter {
                        return char.uppercased()
                    } else if firstChar.isNumber {
                        return char
                    } else {
                        // Handle special characters
                        return mapSpecialCharacter(char)
                    }
                }
            }
        }
        
        // Fallback to key code mapping for special keys
        return mapKeyCode(key.keyCode)
    }
    
    private func mapModifierKeyCode(_ keyCode: UIKeyboardHIDUsage) -> String {
        switch keyCode {
        case .keyboardLeftControl, .keyboardRightControl: return "Ctrl"
        case .keyboardLeftShift, .keyboardRightShift: return "Shift"
        case .keyboardLeftAlt, .keyboardRightAlt: return "Alt"
        case .keyboardLeftGUI, .keyboardRightGUI: return "Cmd"
        default: return "Unknown"
        }
    }
    
    private func mapSpecialCharacter(_ char: String) -> String {
        switch char {
        case "-": return "-"
        case "=": return "="
        case "[": return "["
        case "]": return "]"
        case "\\": return "\\"
        case ";": return ";"
        case "'": return "'"
        case "`": return "`"
        case ",": return ","
        case ".": return "."
        case "/": return "/"
        default: return char
        }
    }
    
    private func mapKeyCode(_ keyCode: UIKeyboardHIDUsage) -> String {
        switch keyCode {
        // Arrow keys
        case .keyboardUpArrow: return "Up"
        case .keyboardDownArrow: return "Down"
        case .keyboardLeftArrow: return "Left"
        case .keyboardRightArrow: return "Right"
        
        // Function keys
        case .keyboardF1: return "F1"
        case .keyboardF2: return "F2"
        case .keyboardF3: return "F3"
        case .keyboardF4: return "F4"
        case .keyboardF5: return "F5"
        case .keyboardF6: return "F6"
        case .keyboardF7: return "F7"
        case .keyboardF8: return "F8"
        case .keyboardF9: return "F9"
        case .keyboardF10: return "F10"
        case .keyboardF11: return "F11"
        case .keyboardF12: return "F12"
        
        // Special keys
        case .keyboardEscape: return "Escape"
        case .keyboardDeleteOrBackspace: return "Backspace"
        case .keyboardTab: return "Tab"
        case .keyboardSpacebar: return "Space"
        case .keyboardReturnOrEnter: return "Enter"
        case .keyboardCapsLock: return "Caps"
        case .keyboardDeleteForward: return "Delete"
        case .keyboardInsert: return "Insert"
        case .keyboardHome: return "Home"
        case .keyboardEnd: return "End"
        case .keyboardPageUp: return "PageUp"
        case .keyboardPageDown: return "PageDown"
        
        // Numpad keys
        case .keypad0: return "Numpad0"
        case .keypad1: return "Numpad1"
        case .keypad2: return "Numpad2"
        case .keypad3: return "Numpad3"
        case .keypad4: return "Numpad4"
        case .keypad5: return "Numpad5"
        case .keypad6: return "Numpad6"
        case .keypad7: return "Numpad7"
        case .keypad8: return "Numpad8"
        case .keypad9: return "Numpad9"
        case .keypadPeriod: return "NumpadDot"
        case .keypadSlash: return "NumpadSlash"
        case .keypadAsterisk: return "NumpadAsterisk"
        case .keypadPlus: return "NumpadPlus"
        case .keypadEnter: return "NumpadEnter"
        case .keypadEqualSign: return "NumpadEquals"
        case .keypadNumLock: return "NumLock"
        
        default:
            print("🔍 Unmapped key code: \(keyCode.rawValue)")
            return "Unknown"
        }
    }
    
    // MARK: - Helper Methods
    private func isModifierKey(_ key: String) -> Bool {
        return ["Ctrl", "Shift", "Alt", "Cmd"].contains(key)
    }
    
    // MARK: - Public Methods
    func setKeyboardManager(_ manager: KeyboardInputManager) {
        self.keyboardManager = manager
    }
}

// MARK: - SwiftUI Integration
struct ExternalKeyboardHandlerView: UIViewRepresentable {
    let keyboardManager: KeyboardInputManager
    
    func makeUIView(context: Context) -> ExternalKeyboardHandler {
        let handler = ExternalKeyboardHandler()
        handler.setKeyboardManager(keyboardManager)
        
        // Make it become first responder when created
        DispatchQueue.main.async {
            if handler.canBecomeFirstResponder {
                let success = handler.becomeFirstResponder()
                print("🎮 ExternalKeyboardHandler first responder status: \(success)")
            }
        }
        
        return handler
    }
    
    func updateUIView(_ uiView: ExternalKeyboardHandler, context: Context) {
        // Update the keyboard manager reference if needed
        uiView.setKeyboardManager(keyboardManager)
        
        // Ensure first responder status is maintained
        if !uiView.isFirstResponder && uiView.canBecomeFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }
}
