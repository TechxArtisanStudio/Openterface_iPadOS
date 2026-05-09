//
//  MacroInputManager.swift
//  Openterface_iOS
//

import Foundation
import Combine

// MARK: - Manager

final class MacroInputManager: ObservableObject {
    @Published var macros: [Macro] = [] {
        didSet { persist() }
    }

    private weak var keyboardManager: (any KeyboardInputProtocol)?
    private let defaultsKey = "Macros_v1"

    init(keyboardManager: any KeyboardInputProtocol) {
        self.keyboardManager = keyboardManager
        load()
        seedDefaultsIfNeeded()
    }

    // MARK: - CRUD

    func add(_ macro: Macro) {
        macros.append(macro)
    }

    func update(_ macro: Macro) {
        guard let index = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        macros[index] = macro
    }

    func delete(id: UUID) {
        macros.removeAll { $0.id == id }
    }

    // MARK: - Execution

    func execute(_ macro: Macro) {
        let macrosByID = Dictionary(uniqueKeysWithValues: macros.map { ($0.id, $0) })
        let tokens = expandedTokens(for: macro, macrosByID: macrosByID, visited: [])

        DispatchQueue.global(qos: .userInitiated).async {
            MacroExecutionEngine.run(tokens: tokens, intervalMs: macro.intervalMs, keyboardManager: self.keyboardManager)
        }
    }

    /// Execute a raw key sequence string (used by AI press_key tool)
    func executeKeySequence(_ data: String, intervalMs: Int = 80) {
        let tokens = tokenize(data)
        DispatchQueue.global(qos: .userInitiated).async {
            MacroExecutionEngine.run(tokens: tokens, intervalMs: intervalMs, keyboardManager: self.keyboardManager)
        }
    }

    // MARK: - Tokenization

    func tokenize(_ str: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "</?[A-Za-z][A-Za-z0-9]*(?::[A-Za-z0-9-]+)?>")
        else {
            return str.map { String($0) }
        }

        var tokens: [String] = []
        var lastEnd = str.startIndex
        let nsString = str as NSString

        let matches = regex.matches(in: str, range: NSRange(str.startIndex..., in: str))
        for match in matches {
            let matchRange = Range(match.range, in: str)!
            if matchRange.lowerBound > lastEnd {
                let plainText = String(str[lastEnd..<matchRange.lowerBound])
                for ch in plainText {
                    tokens.append(String(ch))
                }
            }
            tokens.append(nsString.substring(with: match.range))
            lastEnd = matchRange.upperBound
        }

        if lastEnd < str.endIndex {
            for ch in str[lastEnd...] {
                tokens.append(String(ch))
            }
        }

        return tokens
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([Macro].self, from: data)
        else { return }
        macros = saved
    }

    // MARK: - Default Macros

    private func seedDefaultsIfNeeded() {
        guard macros.isEmpty else { return }
        let defaults = [
            Macro(
                label: "Copy",
                description: "Copy selection (Ctrl+C)",
                data: "<CTRL>c</CTRL>",
                icon: "doc.on.doc.fill",
                targetSystem: .windows,
                intervalMs: 80
            ),
            Macro(
                label: "Paste",
                description: "Paste clipboard (Ctrl+V)",
                data: "<CTRL>v</CTRL>",
                icon: "clipboard.fill",
                targetSystem: .windows,
                intervalMs: 80
            ),
            Macro(
                label: "Select All",
                description: "Select all content (Ctrl+A)",
                data: "<CTRL>a</CTRL>",
                icon: "checkmark.circle.fill",
                targetSystem: .windows,
                intervalMs: 80
            ),
            Macro(
                label: "Switch Apps",
                description: "Switch between apps (Alt+Tab)",
                data: "<ALT><TAB></ALT>",
                icon: "arrow.swap",
                targetSystem: .windows,
                intervalMs: 200
            )
        ]
        macros = defaults
    }
}

// MARK: - Token Expansion (recursive macro references)

private extension MacroInputManager {
    func expandedTokens(for macro: Macro, macrosByID: [UUID: Macro], visited: Set<UUID>) -> [String] {
        var expanded: [String] = []
        for token in tokenize(macro.data) {
            guard let referencedID = macroReferenceID(from: token),
                  let referencedMacro = macrosByID[referencedID],
                  !visited.contains(referencedID)
            else {
                if macroReferenceID(from: token) == nil {
                    expanded.append(token)
                }
                continue
            }
            expanded.append(contentsOf: expandedTokens(
                for: referencedMacro,
                macrosByID: macrosByID,
                visited: visited.union([referencedID])))
        }
        return expanded
    }

    func macroReferenceID(from token: String) -> UUID? {
        let upper = token.uppercased()
        guard upper.hasPrefix("<MACRO:"), token.hasSuffix(">") else { return nil }
        let startIndex = token.index(token.startIndex, offsetBy: 7)
        let endIndex = token.index(before: token.endIndex)
        return UUID(uuidString: String(token[startIndex..<endIndex]))
    }
}

// MARK: - Execution Engine

private struct MacroExecutionEngine {
    private static let delayTokens: Set<String> = [
        "<DELAY05S>", "<DELAY1S>", "<DELAY2S>", "<DELAY5S>", "<DELAY10S>"
    ]

    private static let modifierOpenClose: [String: String] = [
        "<CTRL>": "Ctrl",
        "<SHIFT>": "Shift",
        "<ALT>": "Alt",
        "<CMD>": "Cmd"
    ]

    private static let specialKeyMap: [String: String] = [
        "<ESC>": "Escape",
        "<BACK>": "Backspace",
        "<ENTER>": "Enter",
        "<TAB>": "Tab",
        "<SPACE>": "Space",
        "<LEFT>": "LeftArrow",
        "<RIGHT>": "RightArrow",
        "<UP>": "UpArrow",
        "<DOWN>": "DownArrow",
        "<HOME>": "Home",
        "<END>": "End",
        "<DEL>": "Delete",
        "<PGUP>": "PageUp",
        "<PGDN>": "PageDown",
        "<F1>": "F1", "<F2>": "F2", "<F3>": "F3", "<F4>": "F4",
        "<F5>": "F5", "<F6>": "F6", "<F7>": "F7", "<F8>": "F8",
        "<F9>": "F9", "<F10>": "F10", "<F11>": "F11", "<F12>": "F12"
    ]

    private static let delayDurations: [String: useconds_t] = [
        "<DELAY05S>": 500_000,
        "<DELAY1S>": 1_000_000,
        "<DELAY2S>": 2_000_000,
        "<DELAY5S>": 5_000_000,
        "<DELAY10S>": 10_000_000
    ]

    // Canonical token aliases
    private static func canonicalToken(_ token: String) -> String {
        let upper = token.uppercased()
        switch upper {
        case "<CONTROL>", "<CTRL>", "<CNTL>": return "<CTRL>"
        case "</CONTROL>", "</CTRL>", "</CNTL>": return "</CTRL>"
        case "<OPTION>", "<OPT>", "<ALT>": return "<ALT>"
        case "</OPTION>", "</OPT>", "</ALT>": return "</ALT>"
        case "<COMMAND>", "<CMD>", "<WIN>", "<SUPER>", "<META>": return "<CMD>"
        case "</COMMAND>", "</CMD>", "</WIN>", "</SUPER>", "</META>": return "</CMD>"
        case "<BACKSPACE>", "<BACK>": return "<BACK>"
        case "</BACKSPACE>", "</BACK>": return "</BACK>"
        case "<RETURN>", "<ENTER>": return "<ENTER>"
        case "</RETURN>", "</ENTER>": return "</ENTER>"
        case "<DELETE>", "<DEL>": return "<DEL>"
        case "</DELETE>", "</DEL>": return "</DEL>"
        default: return upper
        }
    }

    static func run(tokens: [String], intervalMs: Int, keyboardManager: (any KeyboardInputProtocol)?) {
        var pendingModifiers: Set<String> = []

        for token in tokens {
            let normalized = canonicalToken(token)

            // Modifier open
            if let modName = modifierOpenClose[normalized], normalized.hasPrefix("<") && !normalized.hasPrefix("</") {
                pendingModifiers.insert(modName)
                continue
            }

            // Modifier close
            if normalized.hasPrefix("</") {
                let inner = normalized.dropFirst(2).dropLast()
                if let modName = modifierOpenClose["<\(inner)>"] {
                    pendingModifiers.remove(modName)
                }
                continue
            }

            // Delay
            if let duration = delayDurations[normalized] {
                usleep(duration)
                continue
            }

            // Special key
            if let hidKey = specialKeyMap[normalized] {
                sendKeyWithModifiers(hidKey, pendingModifiers, keyboardManager)
                if intervalMs > 10 {
                    usleep(useconds_t(intervalMs * 1_000))
                }
                continue
            }

            // Plain character
            if normalized.count == 1, let ch = normalized.first {
                sendCharWithModifiers(ch, pendingModifiers, keyboardManager)
                if intervalMs > 10 {
                    usleep(useconds_t(intervalMs * 1_000))
                }
                continue
            }
        }
    }

    private static func sendKeyWithModifiers(_ key: String, _ mods: Set<String>, _ km: (any KeyboardInputProtocol)?) {
        DispatchQueue.main.sync {
            let modifierNames = Array(mods)
            km?.handleKeyCombo(modifiers: modifierNames, key: key)
        }
    }

    private static func sendCharWithModifiers(_ char: Character, _ mods: Set<String>, _ km: (any KeyboardInputProtocol)?) {
        let ch = String(char)
        let upper = ch.uppercased()

        // Letters and digits: use key combo with auto-shift
        if let ascii = char.asciiValue,
           (ascii >= 97 && ascii <= 122) || (ascii >= 65 && ascii <= 90) ||
           (ascii >= 48 && ascii <= 57) {
            var effectiveMods = mods
            if char.isUppercase {
                effectiveMods.insert("Shift")
            }
            sendKeyWithModifiers(upper, effectiveMods, km)
            return
        }

        // Other single characters: use text input
        DispatchQueue.main.sync {
            km?.handleTextInput(ch)
        }
    }
}
