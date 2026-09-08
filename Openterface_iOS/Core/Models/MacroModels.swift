//
//  MacroModels.swift
//  Openterface_iOS
//

import Foundation

/// Target operating system running on the controlled (target) machine.
/// Mirrors KeyCmd's 3-system model: Windows / macOS / Linux.
enum MacroTargetSystem: String, Codable, CaseIterable, Identifiable {
    case macOS
    case windows
    case linux

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .windows: return "Windows"
        case .linux: return "Linux"
        }
    }

    var sfSymbol: String {
        switch self {
        case .macOS: return "applelogo"
        case .windows: return "pc"
        case .linux: return "terminal"
        }
    }

    // MARK: - Keyboard semantics (KeyCmd-aligned)

    /// True for macOS — the only target that uses the ⌘ Command key as primary.
    var isMacStyle: Bool { self == .macOS }

    /// Primary modifier used by cross-platform semantic shortcuts
    /// (Select All / Copy / Cut / Paste / Save / Undo …).
    var primaryModifier: String { isMacStyle ? "Cmd" : "Ctrl" }

    /// Display name of the GUI key (HID 0x08) on each target's physical keyboard.
    var guiKeyName: String {
        switch self {
        case .macOS: return "Cmd"
        case .windows: return "Win"
        case .linux: return "Super"
        }
    }

    /// SF-Symbol-friendly label for the GUI key.
    var guiKeyLabel: String {
        switch self {
        case .macOS: return "⌘"
        case .windows: return "⊞"
        case .linux: return "❖"
        }
    }

    /// Codable decoding with backward-compatible fallback for legacy values
    /// ("iOS" / "android" persisted by older builds) → treated as .windows
    /// (Ctrl-style), matching KeyCmd's non-Mac semantics.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "macos": self = .macOS
        case "windows", "ios": self = .windows
        case "linux", "android": self = .linux
        default: self = .windows
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A macro is a tokenized sequence of keystrokes that can be played back
struct Macro: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var description: String
    var isVerified: Bool
    var data: String
    var icon: String
    var targetSystem: MacroTargetSystem
    var intervalMs: Int

    init(
        id: UUID = UUID(),
        label: String,
        description: String = "",
        isVerified: Bool = false,
        data: String,
        icon: String = "keyboard.fill",
        targetSystem: MacroTargetSystem = .windows,
        intervalMs: Int = 80
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.isVerified = isVerified
        self.data = data
        self.icon = icon
        self.targetSystem = targetSystem
        self.intervalMs = intervalMs
    }

    // MARK: - CodingKeys (backward-compatible defaults)

    enum CodingKeys: String, CodingKey {
        case id, label, description, isVerified, data, icon, targetSystem, intervalMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        data = try container.decodeIfPresent(String.self, forKey: .data) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "keyboard.fill"
        targetSystem = try container.decodeIfPresent(MacroTargetSystem.self, forKey: .targetSystem) ?? .windows
        intervalMs = try container.decodeIfPresent(Int.self, forKey: .intervalMs) ?? 80
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(description, forKey: .description)
        try container.encode(isVerified, forKey: .isVerified)
        try container.encode(data, forKey: .data)
        try container.encode(icon, forKey: .icon)
        try container.encode(targetSystem, forKey: .targetSystem)
        try container.encode(intervalMs, forKey: .intervalMs)
    }
}
