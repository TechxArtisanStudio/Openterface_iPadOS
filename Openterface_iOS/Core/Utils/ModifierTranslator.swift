//
//  ModifierTranslator.swift
//  Openterface_iOS
//
//  Utility to translate modifier strings based on target OS semantics.
//  Mirrors KeyCmd's approach: Cmd key maps to primary modifier (Cmd on macOS, Ctrl elsewhere).
//

import Foundation

/// Translates a modifier string according to target OS semantics.
/// - Non-macOS targets treat "Cmd" as "Ctrl" (the primary modifier on Windows/Linux).
/// - Other modifiers (Ctrl, Alt, Shift) remain unchanged.
struct ModifierTranslator {
    /// Translate a single modifier string.
    /// - Parameter modifier: Raw modifier string (e.g. "Cmd", "Ctrl+Shift")
    /// - Parameter targetOS: Current target operating system
    /// - Returns: Translated modifier string suitable for sending to target.
    static func translate(_ modifier: String, for targetOS: MacroTargetSystem) -> String {
        guard !modifier.isEmpty else { return modifier }

        // If target is macOS, no translation needed.
        if targetOS.isMacStyle { return modifier }

        // Non-macOS: translate Cmd → Ctrl
        let parts = modifier.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let translated = parts.map { part in
            if part.lowercased() == "cmd" {
                return "Ctrl"
            }
            return part
        }
        return translated.joined(separator: "+")
    }

    /// Translate an array of modifier strings.
    static func translate(_ modifiers: [String], for targetOS: MacroTargetSystem) -> [String] {
        return modifiers.map { translate($0, for: targetOS) }
    }
}