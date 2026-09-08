//
//  Extensions.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import SwiftUI
import CoreGraphics

// MARK: - String Extensions
extension String {
    /// Check if string represents a letter key
    var isLetterKey: Bool {
        return self.count == 1 && self.first?.isLetter == true
    }
    
    /// Check if string represents a modifier key
    var isModifierKey: Bool {
        return ["Ctrl", "Shift", "Alt", "Cmd", "Win", "Super", "Caps"].contains(self)
    }
    
    /// Get display name for special keys
    var keyDisplayName: String {
        switch self {
        case "Backspace": return "⌫"
        case "Enter": return "↵"
        case "Shift": return "⇧"
        case "Ctrl": return "⌃"
        case "Alt": return "⌥"
        case "Cmd": return "⌘"
        case "Win": return "⊞"
        case "Super": return "❖"
        case "Caps": return "⇪"
        case "Space": return "␣"
        case "Tab": return "⇥"
        case "Escape", "Esc": return "⎋"
        case "Delete", "Del": return "⌦"
        case "Up": return "↑"
        case "Down": return "↓"
        case "Left": return "←"
        case "Right": return "→"
        default: return self
        }
    }
}

// MARK: - Color Extensions
extension Color {
    /// Signal strength colors
    static let signalExcellent = Color.green
    static let signalGood = Color.blue
    static let signalFair = Color.orange
    static let signalPoor = Color.red
    
    /// App theme colors
    static let primaryAccent = Color.blue
    static let secondaryAccent = Color.gray
    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    
    /// Create color from signal strength
    static func fromSignalStrength(_ strength: SignalStrength) -> Color {
        switch strength {
        case .excellent: return .signalExcellent
        case .good: return .signalGood
        case .fair: return .signalFair
        case .poor: return .signalPoor
        }
    }
}

// MARK: - CGPoint Extensions
extension CGPoint {
    /// Create point with equal x and y values
    init(_ value: CGFloat) {
        self.init(x: value, y: value)
    }
    
    /// Calculate distance to another point
    func distance(to point: CGPoint) -> CGFloat {
        let dx = self.x - point.x
        let dy = self.y - point.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Add two points
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    /// Subtract two points
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    
    /// Multiply point by scalar
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        return CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

// MARK: - View Extensions
extension View {
    /// Add conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Add haptic feedback
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.impactOccurred()
        }
    }
    
    /// Apply keyboard button styling
    func keyboardButtonStyle(
        isPressed: Bool = false,
        isModifier: Bool = false,
        isActive: Bool = false
    ) -> some View {
        self
            .background(
                isPressed ? Color.blue.opacity(0.9) :
                isActive ? Color.blue.opacity(0.6) :
                isModifier ? Color(UIColor.tertiarySystemBackground) :
                Color(UIColor.systemBackground)
            )
            .foregroundColor(
                (isPressed || isActive) ? .white : .primary
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Bundle Extensions
extension Bundle {
    /// App version string
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    /// App build number
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    /// App display name
    var appDisplayName: String {
        return infoDictionary?["CFBundleDisplayName"] as? String ?? "Openterface iOS"
    }
}

// MARK: - Date Extensions
extension Date {
    /// Check if date is within last few seconds
    func isRecent(within seconds: TimeInterval = 5.0) -> Bool {
        return timeIntervalSinceNow > -seconds
    }
    
    /// Format for debug logging
    var debugDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: self)
    }
}

// MARK: - Int8 Extensions
extension Int8 {
    /// Create Int8 by clamping Int value
    init(clamping value: Int) {
        if value > Int(Int8.max) {
            self = Int8.max
        } else if value < Int(Int8.min) {
            self = Int8.min
        } else {
            self = Int8(value)
        }
    }
}

// MARK: - Array Extensions
extension Array where Element == UInt8 {
    /// Convert to hex string for debugging
    var hexString: String {
        return self.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Calculate checksum
    var checksum: UInt8 {
        let sum = self.reduce(0 as UInt32) { $0 + UInt32($1) }
        return UInt8(sum & 0xFF)
    }
}
