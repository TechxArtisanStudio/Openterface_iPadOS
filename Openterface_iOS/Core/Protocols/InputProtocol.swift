//
//  InputProtocol.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreGraphics

/// Protocol defining input handling capabilities
protocol InputHandlerProtocol: ObservableObject {
    /// Handle input event
    func handleInput<T>(_ input: T)
}

/// Protocol for keyboard input handling
protocol KeyboardInputProtocol: InputHandlerProtocol {
    /// Active modifier keys
    var activeModifiers: Set<String> { get }
    
    /// Caps lock state
    var capsLockActive: Bool { get }
    
    /// Currently pressed keys
    var pressedKeys: Set<String> { get }
    
    /// Handle key press
    func handleKeyPress(_ key: String)
    
    /// Handle key release
    func handleKeyRelease(_ key: String)
    
    /// Handle modifier toggle
    func handleModifierToggle(_ modifier: String)
    
    /// Handle key combination
    func handleKeyCombo(modifiers: [String], key: String)
    
    /// Handle text input
    func handleTextInput(_ text: String)
}

/// Protocol for mouse input handling
protocol MouseInputProtocol: InputHandlerProtocol {
    /// Current mouse position
    var currentPosition: CGPoint? { get }
    
    /// Selection/drag mode state
    var isSelectMode: Bool { get }
    
    /// Handle mouse movement
    func handleMouseMove(delta: CGPoint)
    
    /// Handle mouse click
    func handleMouseClick(button: MouseButton, action: MouseAction)
    
    /// Handle drag gesture
    func handleDragGesture(start: CGPoint, current: CGPoint, end: CGPoint?)
    
    /// Handle scroll gesture
    func handleScroll(delta: CGPoint)
}

/// Mouse button types
enum MouseButton {
    case left
    case right
    case middle
}

/// Mouse action types
enum MouseAction {
    case press
    case release
    case click
    case doubleClick
}

/// Protocol for composite key management
protocol CompositeKeyProtocol {
    associatedtype KeyCombo
    
    /// Available key combinations
    var availableKeyCombo: [KeyCombo] { get }
    
    /// Execute key combination
    func executeKeyCombo(_ combo: KeyCombo)
    
    /// Get key combinations by category
    func getKeyCombo(for category: String) -> [KeyCombo]
}
