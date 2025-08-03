//
//  CompositeKeyInputManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation

final class CompositeKeyInputManager: ObservableObject {
    // MARK: - Properties
    private weak var keyboardManager: (any KeyboardInputProtocol)?
    
    // MARK: - Available Key Combinations
    lazy var availableKeyCombo: [KeyCombo] = [
        // Navigation
        KeyCombo(id: "copy", displayName: "Ctrl+C", modifiers: ["Ctrl"], key: "C", category: .navigation, description: "Copy"),
        KeyCombo(id: "paste", displayName: "Ctrl+V", modifiers: ["Ctrl"], key: "V", category: .navigation, description: "Paste"),
        KeyCombo(id: "cut", displayName: "Ctrl+X", modifiers: ["Ctrl"], key: "X", category: .navigation, description: "Cut"),
        KeyCombo(id: "selectAll", displayName: "Ctrl+A", modifiers: ["Ctrl"], key: "A", category: .navigation, description: "Select All"),
        KeyCombo(id: "find", displayName: "Ctrl+F", modifiers: ["Ctrl"], key: "F", category: .navigation, description: "Find"),
        KeyCombo(id: "replace", displayName: "Ctrl+H", modifiers: ["Ctrl"], key: "H", category: .navigation, description: "Replace"),
        KeyCombo(id: "goToLine", displayName: "Ctrl+G", modifiers: ["Ctrl"], key: "G", category: .navigation, description: "Go to Line"),
        KeyCombo(id: "home", displayName: "Ctrl+Home", modifiers: ["Ctrl"], key: "Home", category: .navigation, description: "Go to Beginning"),
        KeyCombo(id: "end", displayName: "Ctrl+End", modifiers: ["Ctrl"], key: "End", category: .navigation, description: "Go to End"),
        KeyCombo(id: "pageUp", displayName: "Page Up", modifiers: [], key: "PageUp", category: .navigation, description: "Page Up"),
        KeyCombo(id: "pageDown", displayName: "Page Down", modifiers: [], key: "PageDown", category: .navigation, description: "Page Down"),
        
        // System
        KeyCombo(id: "newTab", displayName: "Ctrl+T", modifiers: ["Ctrl"], key: "T", category: .system, description: "New Tab"),
        KeyCombo(id: "closeTab", displayName: "Ctrl+W", modifiers: ["Ctrl"], key: "W", category: .system, description: "Close Tab"),
        KeyCombo(id: "newWindow", displayName: "Ctrl+N", modifiers: ["Ctrl"], key: "N", category: .system, description: "New Window"),
        KeyCombo(id: "openFile", displayName: "Ctrl+O", modifiers: ["Ctrl"], key: "O", category: .system, description: "Open File"),
        KeyCombo(id: "save", displayName: "Ctrl+S", modifiers: ["Ctrl"], key: "S", category: .system, description: "Save"),
        KeyCombo(id: "saveAs", displayName: "Ctrl+Shift+S", modifiers: ["Ctrl", "Shift"], key: "S", category: .system, description: "Save As"),
        KeyCombo(id: "print", displayName: "Ctrl+P", modifiers: ["Ctrl"], key: "P", category: .system, description: "Print"),
        KeyCombo(id: "refresh", displayName: "Ctrl+R", modifiers: ["Ctrl"], key: "R", category: .system, description: "Refresh"),
        KeyCombo(id: "fullScreen", displayName: "F11", modifiers: [], key: "F11", category: .system, description: "Toggle Full Screen"),
        KeyCombo(id: "quit", displayName: "Alt+F4", modifiers: ["Alt"], key: "F4", category: .system, description: "Quit Application"),
        
        // Application
        KeyCombo(id: "switchApp", displayName: "Alt+Tab", modifiers: ["Alt"], key: "Tab", category: .application, description: "Switch Application"),
        KeyCombo(id: "minimize", displayName: "Cmd+M", modifiers: ["Cmd"], key: "M", category: .application, description: "Minimize Window"),
        KeyCombo(id: "closeWindow", displayName: "Cmd+W", modifiers: ["Cmd"], key: "W", category: .application, description: "Close Window"),
        KeyCombo(id: "showDesktop", displayName: "Cmd+D", modifiers: ["Cmd"], key: "D", category: .application, description: "Show Desktop"),
        KeyCombo(id: "lockScreen", displayName: "Cmd+L", modifiers: ["Cmd"], key: "L", category: .application, description: "Lock Screen"),
        KeyCombo(id: "screenshot", displayName: "Cmd+Shift+3", modifiers: ["Cmd", "Shift"], key: "3", category: .application, description: "Screenshot"),
        KeyCombo(id: "partialScreenshot", displayName: "Cmd+Shift+4", modifiers: ["Cmd", "Shift"], key: "4", category: .application, description: "Partial Screenshot"),
        
        // Editing
        KeyCombo(id: "undo", displayName: "Ctrl+Z", modifiers: ["Ctrl"], key: "Z", category: .editing, description: "Undo"),
        KeyCombo(id: "redo", displayName: "Ctrl+Y", modifiers: ["Ctrl"], key: "Y", category: .editing, description: "Redo"),
        KeyCombo(id: "bold", displayName: "Ctrl+B", modifiers: ["Ctrl"], key: "B", category: .editing, description: "Bold text"),
        KeyCombo(id: "italic", displayName: "Ctrl+I", modifiers: ["Ctrl"], key: "I", category: .editing, description: "Italic text"),
        KeyCombo(id: "underline", displayName: "Ctrl+U", modifiers: ["Ctrl"], key: "U", category: .editing, description: "Underline text"),
        KeyCombo(id: "duplicate", displayName: "Ctrl+D", modifiers: ["Ctrl"], key: "D", category: .editing, description: "Duplicate line")
    ]
    
    // MARK: - Initialization
    init() {}
    
    func setKeyboardManager(_ manager: any KeyboardInputProtocol) {
        self.keyboardManager = manager
    }
}

// MARK: - CompositeKeyProtocol Conformance
extension CompositeKeyInputManager: CompositeKeyProtocol {    
    func executeKeyCombo(_ combo: KeyCombo) {
        print("🎯 Executing key combo: \(combo.displayName)")
        keyboardManager?.handleKeyCombo(modifiers: combo.modifiers, key: combo.key)
    }
    
    func getKeyCombo(for category: String) -> [KeyCombo] {
        guard let keyCategory = KeyCategory(rawValue: category) else {
            return []
        }
        
        return availableKeyCombo.filter { $0.category == keyCategory }
    }
}

// MARK: - Public Methods
extension CompositeKeyInputManager {
    /// Get all categories with their key combinations count
    func getCategoriesWithCount() -> [(category: KeyCategory, count: Int)] {
        let categories = KeyCategory.allCases
        return categories.map { category in
            let count = availableKeyCombo.filter { $0.category == category }.count
            return (category: category, count: count)
        }
    }
    
    /// Search key combinations by name or description
    func searchKeyCombo(query: String) -> [KeyCombo] {
        let lowercaseQuery = query.lowercased()
        return availableKeyCombo.filter { combo in
            combo.displayName.lowercased().contains(lowercaseQuery) ||
            combo.description.lowercased().contains(lowercaseQuery) ||
            combo.key.lowercased().contains(lowercaseQuery)
        }
    }
    
    /// Get most commonly used key combinations
    func getCommonKeyCombo() -> [KeyCombo] {
        let commonIds = ["copy", "paste", "cut", "selectAll", "save", "undo", "redo"]
        return availableKeyCombo.filter { commonIds.contains($0.id) }
    }
    
    /// Execute key combination by ID
    func executeKeyCombo(withId id: String) {
        guard let combo = availableKeyCombo.first(where: { $0.id == id }) else {
            print("❌ Key combo with ID '\(id)' not found")
            return
        }
        self.executeKeyCombo(combo)
    }
}
