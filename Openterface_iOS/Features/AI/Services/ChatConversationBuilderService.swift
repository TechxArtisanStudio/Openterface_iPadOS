//
//  ChatConversationBuilderService.swift
//  Openterface_iOS
//

import Foundation
import UIKit

final class ChatConversationBuilderService {

    private let macroManager: MacroInputManager
    private let targetOS: () -> MacroTargetSystem

    init(macroManager: MacroInputManager, targetOS: @escaping () -> MacroTargetSystem) {
        self.macroManager = macroManager
        self.targetOS = targetOS
    }

    // MARK: - Agent Tool Instruction

    let agentToolInstruction = """
When action is required, you may call tools by returning ONLY JSON (no markdown):
{"tool_calls":[{"tool":"capture_screen"},{"tool":"move_mouse","x":0.5,"y":0.5},{"tool":"left_click"},{"tool":"left_drag","start_x":0.2,"start_y":0.5,"x":0.8,"y":0.5},{"tool":"type_text","text":"hello"},{"tool":"run_verified_macro","macro_id":"UUID-or-label"}]}

The target OS has already been configured by the app. Do not ask the user to confirm the OS again.

Coordinate system:
- All x/y values are normalized floats from 0.0 to 1.0.
- 0.0 means the left/top edge of the screen; 1.0 means the right/bottom edge.
- Estimate the element's position as a fraction of the screenshot width and height.
- Example: if a button is at roughly 45% from left and 30% from top, use x=0.45, y=0.30.
- NEVER output raw pixel coordinates. Always use 0.0-1.0 normalized values.

Available tools:
- capture_screen: Capture latest target screen and use it for next reasoning step.
- move_mouse: Move target mouse. Args: x (Float), y (Float) in 0.0...1.0.
- left_click: Left click at current mouse location. Optional args: x (Float), y (Float) in 0.0...1.0.
- left_drag: Hold left mouse button and drag to a destination. Args: x (Float), y (Float) destination in 0.0...1.0. Optional args: start_x (Float), start_y (Float) to begin from a specific point; otherwise current mouse position is used.
- right_click: Right click at current mouse location. Optional args: x (Float), y (Float) in 0.0...1.0.
- double_click: Double left click. Optional args: x (Float), y (Float) in 0.0...1.0.
- type_text: Type PLAIN TEXT on target. Args: text (String). ONLY use this for literal characters. Do NOT pass token sequences like <DOWN>, <ENTER>, <ESC> here — use press_key instead.
- press_key: Press one or more special keys or a key combination. Args: keys (String) — a sequence of key tokens from this list: <ESC> <ENTER> <TAB> <SPACE> <BACK> <DEL> <UP> <DOWN> <LEFT> <RIGHT> <HOME> <END> <PGUP> <PGDN> <F1>..<F12>. Wrap with modifier tags: <CTRL>c</CTRL> <CMD>a</CMD> <SHIFT><TAB></SHIFT> <ALT><F4></ALT>. Example: {"tool":"press_key","keys":"<DOWN>"} or {"tool":"press_key","keys":"<CTRL>c</CTRL>"}.
- run_verified_macro: Execute one verified macro. Args: macro_id (String, preferred UUID) or macro_label (String).
- create_macro: Create a new macro. Required args: label (String), data (String, macro key sequence). Optional args: description (String), target_system (String), interval_ms (Int, default 80), verified (Bool, default false).
- set_macro_verified: Set or clear the verified flag on an existing macro. Required args: macro_id (String UUID) or macro_label (String). Required args: verified (Bool).

Macro tool rules:
- Prefer run_verified_macro when a verified macro can jump directly to the requested state.
- Before using capture_screen or incremental mouse steps, check whether a verified macro already matches the user's current goal or sub-goal and use it first when it is a strong fit.
- Only call run_verified_macro with a verified macro from the provided macro inventory.
- Prefer macro_id over macro_label when available.
- IMPORTANT: After running a macro, always verify the result in a NEW tool_calls response. Never include capture_screen or any other tool in the same tool_calls array as run_verified_macro, because the macro needs time to complete on the target machine before a screenshot is useful.
- If the macro partially completes the job, continue with more tool calls until the task is actually complete.
- If no verified macro matches, continue with the normal screen-driven tools.

Mouse safety rules:
- Only click when the intended target is clearly visible in the latest screenshot.
- Do not guess hidden Dock icons, hidden windows, or off-screen control locations.
- If a macro or shortcut did not bring the expected app/window to the foreground, prefer another verified macro, keyboard-driven recovery, or another capture_screen step instead of a blind click.

After tool execution, you will receive a TOOL_RESULT message. Continue until task done, then return normal user-facing text (not JSON).
"""

    // MARK: - Conversation Building

    func buildConversation(
        systemPrompt: String,
        sourceMessages: [ChatMessage],
        includeAgentTools: Bool
    ) -> [ChatCompletionsRequest.Message] {
        var conversation: [ChatCompletionsRequest.Message] = []

        if !systemPrompt.isEmpty {
            conversation.append(.text(role: .system, text: systemPrompt))
        }
        if includeAgentTools {
            conversation.append(.text(role: .system, text: agentToolInstruction + "\n\n" + macroInventoryPrompt()))
        }

        let recent = sourceMessages.suffix(30)

        conversation.append(contentsOf: recent.map { message in
            if message.role == .user,
               let path = message.attachmentFilePath,
               let imageDataURL = dataURLForImage(atPath: path) {
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Please analyze this screenshot."
                    : message.content
                return .multimodal(role: message.role, text: text, imageDataURL: imageDataURL)
            }
            return .text(role: message.role, text: message.content)
        })

        return conversation
    }

    // MARK: - Macro Inventory

    func macroInventoryPrompt() -> String {
        let verifiedMacros = macroManager.macros.filter { $0.isVerified }
        var sections: [String] = []

        if verifiedMacros.isEmpty {
            sections.append("Verified executable macros:\n- No verified macros are currently available.")
        } else {
            let verifiedLines = verifiedMacros.map { macro in
                let description = macro.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = description.isEmpty ? macro.data : description
                return "- id=\(macro.id.uuidString), label=\(macro.label), target=\(macro.targetSystem.displayName), detail=\(detail)"
            }
            sections.append("Verified executable macros:\n" + verifiedLines.joined(separator: "\n"))
        }

        sections.append("Macro tool usage:\n- Use run_verified_macro only with a verified macro from the executable list above.\n- Prefer macro_id over macro_label when calling the tool.\n- IMPORTANT: After running a macro, always verify the result in a NEW tool_calls response. Never include capture_screen or any other tool in the same tool_calls array as run_verified_macro.\n- If the macro gets close but does not fully finish the job, continue with additional tool calls instead of assuming success.")

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Macro Matching

    func anyMacroMatch(from args: [String: Any]) -> MacroMatch? {
        let allMacros = macroManager.macros
        guard !allMacros.isEmpty else { return nil }
        return macroMatch(in: allMacros, from: args)
    }

    func verifiedMacroMatch(from args: [String: Any]) -> MacroMatch? {
        let verifiedMacros = macroManager.macros.filter { $0.isVerified }
        guard !verifiedMacros.isEmpty else { return nil }
        return macroMatch(in: verifiedMacros, from: args)
    }

    private func macroMatch(in macros: [Macro], from args: [String: Any]) -> MacroMatch? {
        let requestedID = ((args["macro_id"] as? String) ?? (args["id"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let macroID = UUID(uuidString: requestedID),
           let matched = macros.first(where: { $0.id == macroID }) {
            return MacroMatch(macro: matched, matchedBy: "id")
        }

        let requestedLabel = ((args["macro_label"] as? String) ?? (args["label"] as? String) ?? requestedID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedLabel.isEmpty else { return nil }

        let normalized = requestedLabel.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let exact = macros.first(where: {
            $0.label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        }) {
            return MacroMatch(macro: exact, matchedBy: "label")
        }

        let partials = macros.filter {
            $0.label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized)
        }
        if partials.count == 1, let matched = partials.first {
            return MacroMatch(macro: matched, matchedBy: "partial-label")
        }
        return nil
    }

    // MARK: - Image Encoding

    func dataURLForImage(atPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let imageData = try? Data(contentsOf: url) else { return nil }

        let ext = url.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "png": mimeType = "image/png"
        case "heic", "heif": mimeType = "image/heic"
        default: mimeType = "image/jpeg"
        }

        // Try to re-encode as JPEG to reduce size for non-JPEG images
        if mimeType != "image/jpeg",
           let image = UIImage(data: imageData),
           let jpegData = image.jpegData(compressionQuality: 0.85) {
            return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        }

        return "data:\(mimeType);base64,\(imageData.base64EncodedString())"
    }

    // MARK: - JSON Payload Decoding

    func decodeJSONPayload<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            throw NSError(domain: "ChatConversationBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No JSON found"])
        }
        let candidate = String(trimmed[start...end])
        guard let data = candidate.data(using: .utf8) else {
            throw NSError(domain: "ChatConversationBuilder", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON is not UTF-8"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct MacroMatch {
    let macro: Macro
    let matchedBy: String
}
