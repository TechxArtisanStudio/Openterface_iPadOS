//
//  ChatToolExecutionService.swift
//  Openterface_iOS
//

import Foundation

final class ChatToolExecutionService {

    private let keyboardManager: KeyboardInputManager
    private let mouseManager: MouseInputManager
    private let macroManager: MacroInputManager
    private let screenCapture: ChatScreenCaptureService
    private let conversationBuilder: ChatConversationBuilderService

    init(
        keyboardManager: KeyboardInputManager,
        mouseManager: MouseInputManager,
        macroManager: MacroInputManager,
        screenCapture: ChatScreenCaptureService,
        conversationBuilder: ChatConversationBuilderService
    ) {
        self.keyboardManager = keyboardManager
        self.mouseManager = mouseManager
        self.macroManager = macroManager
        self.screenCapture = screenCapture
        self.conversationBuilder = conversationBuilder
    }

    // MARK: - Tool-call parsing

    func parseToolCalls(from text: String) -> [AgentToolCall]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("tool") else { return nil }

        let candidate: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            candidate = String(trimmed[start...end])
        } else {
            return nil
        }

        guard let data = candidate.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let dict = json as? [String: Any],
           let calls = dict["tool_calls"] as? [[String: Any]] {
            return calls.compactMap { call in
                guard let tool = call["tool"] as? String else { return nil }
                var args = call
                args.removeValue(forKey: "tool")
                return AgentToolCall(tool: tool, args: args)
            }
        }

        if let dict = json as? [String: Any], let tool = dict["tool"] as? String {
            var args = dict
            args.removeValue(forKey: "tool")
            return [AgentToolCall(tool: tool, args: args)]
        }

        return nil
    }

    // MARK: - Tool dispatch

    func executeToolCalls(_ calls: [AgentToolCall]) async -> AgentToolExecutionResult {
        var summaries: [String] = []
        var attachmentPath: String?
        var keyboardTokens: [String] = []
        var hasNonKeyboardTool = false

        for call in calls {
            let toolName = call.tool.lowercased()
            switch toolName {

            case "capture_screen", "take_screenshot", "screenshot":
                hasNonKeyboardTool = true
                if let fileURL = await screenCapture.captureScreenForAgent() {
                    attachmentPath = fileURL.path
                    summaries.append("capture_screen: success")
                } else {
                    summaries.append("capture_screen: failed (no image captured)")
                }

            case "move_mouse":
                hasNonKeyboardTool = true
                if let nx = doubleArg(call.args["x"]), let ny = doubleArg(call.args["y"]) {
                    let clampedX = max(0.0, min(1.0, nx))
                    let clampedY = max(0.0, min(1.0, ny))
                    mouseManager.clickAtNormalizedPosition(x: clampedX, y: clampedY, button: 0x00)
                    summaries.append("move_mouse: ok (x=\(String(format: "%.3f", clampedX)), y=\(String(format: "%.3f", clampedY)))")
                } else {
                    summaries.append("move_mouse: invalid args")
                }

            case "left_click":
                hasNonKeyboardTool = true
                let point = resolveClickPoint(call.args)
                mouseManager.clickAtNormalizedPosition(x: point.x, y: point.y, button: 0x01)
                summaries.append("left_click: success (x=\(String(format: "%.3f", point.x)), y=\(String(format: "%.3f", point.y)))")

            case "right_click":
                hasNonKeyboardTool = true
                let point = resolveClickPoint(call.args)
                mouseManager.clickAtNormalizedPosition(x: point.x, y: point.y, button: 0x02)
                summaries.append("right_click: success (x=\(String(format: "%.3f", point.x)), y=\(String(format: "%.3f", point.y)))")

            case "double_click":
                hasNonKeyboardTool = true
                let point = resolveClickPoint(call.args)
                mouseManager.doubleClickAtNormalizedPosition(x: point.x, y: point.y, button: 0x01)
                summaries.append("double_click: success (x=\(String(format: "%.3f", point.x)), y=\(String(format: "%.3f", point.y)))")

            case "left_drag", "drag_mouse", "mouse_drag", "drag":
                hasNonKeyboardTool = true
                if let dragPoints = resolveDragPoints(call.args) {
                    mouseManager.dragFromNormalizedPosition(
                        startX: dragPoints.startX, startY: dragPoints.startY,
                        to: dragPoints.endX, endY: dragPoints.endY
                    )
                    summaries.append("left_drag: success")
                } else {
                    summaries.append("left_drag: invalid args")
                }

            case "type_text":
                let text = (call.args["text"] as? String) ?? ""
                if !text.isEmpty { keyboardTokens.append(text) }
                if text.isEmpty {
                    summaries.append("type_text: empty text")
                } else {
                    let looksLikeTokenSequence = text.contains("<") && text.contains(">")
                    if looksLikeTokenSequence {
                        macroManager.executeKeySequence(text, intervalMs: 80)
                        summaries.append("type_text(redirected to press_key): success (keys=\"\(text)\")")
                    } else {
                        keyboardManager.handleTextInput(text)
                        summaries.append("type_text: success (chars=\(text.count))")
                    }
                }

            case "press_key", "key_press", "send_key", "hotkey":
                let keys = ((call.args["keys"] as? String) ?? (call.args["key"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !keys.isEmpty { keyboardTokens.append(keys) }
                if keys.isEmpty {
                    summaries.append("press_key: missing keys argument")
                } else {
                    macroManager.executeKeySequence(keys, intervalMs: 80)
                    summaries.append("press_key: success (keys=\"\(keys)\")")
                }

            case "run_verified_macro", "execute_verified_macro", "invoke_verified_macro":
                hasNonKeyboardTool = true
                if let match = conversationBuilder.verifiedMacroMatch(from: call.args) {
                    macroManager.execute(match.macro)
                    let waitDuration = Double(match.macro.intervalMs) * 0.001 * Double(tokenCount(match.macro.data)) + 1.0
                    try? await Task.sleep(nanoseconds: UInt64(waitDuration * 1_000_000_000))
                    summaries.append("run_verified_macro: success (label=\"\(match.macro.label)\", waitedSeconds=\(String(format: "%.1f", waitDuration)))")
                    summaries.append("run_verified_macro_note: the macro keystrokes have finished; now verify the new screen state with capture_screen before any click")
                } else {
                    let available = macroManager.macros
                        .filter { $0.isVerified }
                        .map { "\($0.label) [\($0.id.uuidString)]" }
                        .joined(separator: ", ")
                    let inventory = available.isEmpty ? "none" : available
                    summaries.append("run_verified_macro: no verified macro matched (available=\(inventory))")
                }

            case "create_macro", "new_macro", "add_macro":
                hasNonKeyboardTool = true
                let label = (call.args["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let data = (call.args["data"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if label.isEmpty || data.isEmpty {
                    summaries.append("create_macro: missing required args label and/or data")
                } else {
                    let description = (call.args["description"] as? String) ?? ""
                    let intervalMs = intArg(call.args["interval_ms"]) ?? 80
                    let verifiedArg = (call.args["verified"] as? Bool) ?? false
                    let newMacro = Macro(
                        label: label,
                        description: description,
                        isVerified: verifiedArg,
                        data: data,
                        intervalMs: intervalMs
                    )
                    macroManager.add(newMacro)
                    summaries.append("create_macro: success (id=\(newMacro.id.uuidString), label=\"\(label)\", verified=\(verifiedArg))")
                }

            case "set_macro_verified", "verify_macro", "unverify_macro":
                hasNonKeyboardTool = true
                let verifiedArg = (call.args["verified"] as? Bool) ?? true
                if let match = conversationBuilder.anyMacroMatch(from: call.args) {
                    if let idx = macroManager.macros.firstIndex(where: { $0.id == match.macro.id }) {
                        var updated = match.macro
                        updated.isVerified = verifiedArg
                        macroManager.update(updated)
                        summaries.append("set_macro_verified: success (label=\"\(match.macro.label)\", verified=\(verifiedArg))")
                    } else {
                        summaries.append("set_macro_verified: macro not found after match")
                    }
                } else {
                    summaries.append("set_macro_verified: no macro matched")
                }

            default:
                hasNonKeyboardTool = true
                summaries.append("\(toolName): unsupported")
            }
        }

        let macroData = (!hasNonKeyboardTool && !keyboardTokens.isEmpty) ? keyboardTokens.joined() : nil
        return AgentToolExecutionResult(
            summary: summaries.joined(separator: "\n"),
            attachmentFilePath: attachmentPath,
            keyboardOnlyMacroData: macroData
        )
    }

    // MARK: - Argument helpers

    private func intArg(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Double { return Int(v) }
        if let v = value as? String { return Int(v) }
        return nil
    }

    private func doubleArg(_ value: Any?) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        if let v = value as? String { return Double(v) }
        return nil
    }

    private func resolveClickPoint(_ args: [String: Any]) -> (x: Double, y: Double) {
        if let nx = doubleArg(args["x"]), let ny = doubleArg(args["y"]) {
            return (max(0.0, min(1.0, nx)), max(0.0, min(1.0, ny)))
        }
        return (0.5, 0.5) // Default to center
    }

    private func resolveDragPoints(_ args: [String: Any]) -> (startX: Double, startY: Double, endX: Double, endY: Double)? {
        guard let endX = doubleArg(args["x"]), let endY = doubleArg(args["y"]) else { return nil }
        let startX = doubleArg(args["start_x"]) ?? 0.5
        let startY = doubleArg(args["start_y"]) ?? 0.5
        return (max(0.0, min(1.0, startX)), max(0.0, min(1.0, startY)),
                max(0.0, min(1.0, endX)), max(0.0, min(1.0, endY)))
    }

    private func tokenCount(_ data: String) -> Int {
        // Rough estimate: count tokens by counting angle-bracket tokens + characters
        let tagCount = data.components(separatedBy: "<").count - 1
        let charCount = data.count - (tagCount * 10) // rough deduction for tag chars
        return max(tagCount, charCount)
    }
}
