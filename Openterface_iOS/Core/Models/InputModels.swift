//
//  InputModels.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreGraphics

/// Key combination model
struct KeyCombo: Identifiable, Hashable {
    let id: String
    let displayName: String
    let modifiers: [String]
    let key: String
    let category: KeyCategory
    let description: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Key combination categories
enum KeyCategory: String, CaseIterable {
    case navigation = "Navigation"
    case editing = "Editing"
    case system = "System"
    case application = "Application"
    
    var icon: String {
        switch self {
        case .navigation: return "arrow.up.arrow.down"
        case .editing: return "pencil"
        case .system: return "gear"
        case .application: return "app"
        }
    }
}

/// Keyboard mode
enum KeyboardMode: String, CaseIterable {
    case normal = "Normal"
    case game = "Game"
    
    var description: String {
        return self.rawValue
    }
    
    var dataPacketHeader: [UInt8] {
        switch self {
        case .normal: return [0x57, 0xAB, 0x00, 0x02, 0x08]
        case .game: return [0x57, 0xAB, 0x00, 0x12, 0x08]
        }
    }
}

/// Mouse gesture model
struct MouseGesture {
    let startPosition: CGPoint
    let currentPosition: CGPoint
    let endPosition: CGPoint?
    let gestureType: MouseGestureType
    let timestamp: Date
}

/// Mouse gesture types
enum MouseGestureType {
    case tap
    case doubleTap
    case drag
    case scroll
    case longPress
}

/// Input event model
struct InputEvent {
    let id: UUID = UUID()
    let timestamp: Date = Date()
    let type: InputEventType
    let data: Any
}

/// Input event types
enum InputEventType {
    case keyPress
    case keyRelease
    case mouseMove
    case mouseClick
    case scroll
    case gesture
}
