//
//  MacroModels.swift
//  Openterface_iOS
//

import Foundation

/// Target operating system for macro key sequences
enum MacroTargetSystem: String, Codable, CaseIterable, Identifiable {
    case macOS
    case windows
    case linux
    case iOS
    case android

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .windows: return "Windows"
        case .linux: return "Linux"
        case .iOS: return "iOS"
        case .android: return "Android"
        }
    }

    var sfSymbol: String {
        switch self {
        case .macOS: return "applelogo"
        case .windows: return "pc"
        case .linux: return "terminal"
        case .iOS: return "iphone"
        case .android: return "phone.fill"
        }
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
