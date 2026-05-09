//
//  MacroEditorView.swift
//  Openterface_iOS
//

import SwiftUI

struct MacroEditorView: View {
    @ObservedObject var macroManager: MacroInputManager
    @Environment(\.dismiss) var dismiss

    let editingMacro: Macro?
    let globalTargetOS: MacroTargetSystem?

    // Form state
    @State private var label = ""
    @State private var description = ""
    @State private var isVerified = false
    @State private var targetSystem: MacroTargetSystem = .windows
    @State private var data = ""
    @State private var intervalMs = 80
    @State private var shortcutTab = 0

    init(macroManager: MacroInputManager, editingMacro: Macro? = nil, globalTargetOS: MacroTargetSystem? = nil) {
        self.macroManager = macroManager
        self.editingMacro = editingMacro
        self.globalTargetOS = globalTargetOS

        if let editingMacro {
            _label = State(initialValue: editingMacro.label)
            _description = State(initialValue: editingMacro.description)
            _isVerified = State(initialValue: editingMacro.isVerified)
            _targetSystem = State(initialValue: editingMacro.targetSystem)
            _data = State(initialValue: editingMacro.data)
            _intervalMs = State(initialValue: editingMacro.intervalMs)
        } else if let globalTargetOS {
            _targetSystem = State(initialValue: globalTargetOS)
        }
    }

    var isEditing: Bool { editingMacro != nil }

    var body: some View {
        NavigationView {
            Form {
                // Basic info section
                Section("Details") {
                    TextField("Name", text: $label)
                    TextField("Description", text: $description)
                    Toggle("Verified", isOn: $isVerified)
                    Picker("Target System", selection: $targetSystem) {
                        ForEach(MacroTargetSystem.allCases) { system in
                            Text(system.displayName).tag(system)
                        }
                    }
                }

                // Key sequence section
                Section("Key Sequence") {
                    macroSequenceEditor

                    // Shortcut tabs
                    shortcutTabs

                    // Active shortcut content
                    shortcutContent
                }

                // Timing section
                Section("Timing") {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("\(intervalMs)ms")
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Double(intervalMs) },
                            set: { intervalMs = Int($0) }
                        ), in: 10...500, step: 10)
                            .frame(width: 150)
                    }
                }

                // Actions section
                Section {
                    Button(action: save) {
                        Text(isEditing ? "Update Macro" : "Create Macro")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(label.isEmpty || data.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                    .disabled(label.isEmpty || data.isEmpty)

                    if isEditing {
                        Button(role: .destructive, action: delete) {
                            Text("Delete Macro")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Macro" : "New Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sequence Editor

    private var macroSequenceEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sequence")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $data)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shortcut Tabs

    private var shortcutTabs: some View {
        Picker("Shortcuts", selection: $shortcutTab) {
            Text("Keys").tag(0)
            Text("Combos").tag(1)
            Text("Macros").tag(2)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Shortcut Content

    @ViewBuilder
    private var shortcutContent: some View {
        switch shortcutTab {
        case 0: functionKeyShortcuts
        case 1: compositeKeyShortcuts
        default: macroReferenceShortcuts
        }
    }

    // MARK: - Function Key Shortcuts

    private var functionKeyShortcuts: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
            ShortcutButton(token: "<ESC>", label: "Esc") { appendToken("<ESC>") }
            ShortcutButton(token: "<BACK>", label: "Back") { appendToken("<BACK>") }
            ShortcutButton(token: "<ENTER>", label: "Enter") { appendToken("<ENTER>") }
            ShortcutButton(token: "<TAB>", label: "Tab") { appendToken("<TAB>") }
            ShortcutButton(token: "<SPACE>", label: "Space") { appendToken("<SPACE>") }

            ShortcutButton(token: "<LEFT>", label: "Left") { appendToken("<LEFT>") }
            ShortcutButton(token: "<RIGHT>", label: "Right") { appendToken("<RIGHT>") }
            ShortcutButton(token: "<UP>", label: "Up") { appendToken("<UP>") }
            ShortcutButton(token: "<DOWN>", label: "Down") { appendToken("<DOWN>") }
            ShortcutButton(token: "<HOME>", label: "Home") { appendToken("<HOME>") }

            ShortcutButton(token: "<END>", label: "End") { appendToken("<END>") }
            ShortcutButton(token: "<DEL>", label: "Del") { appendToken("<DEL>") }
            ShortcutButton(token: "<PGUP>", label: "PgUp") { appendToken("<PGUP>") }
            ShortcutButton(token: "<PGDN>", label: "PgDn") { appendToken("<PGDN>") }
            ShortcutButton(token: "<F1>", label: "F1") { appendToken("<F1>") }

            ShortcutButton(token: "<F2>", label: "F2") { appendToken("<F2>") }
            ShortcutButton(token: "<F3>", label: "F3") { appendToken("<F3>") }
            ShortcutButton(token: "<F4>", label: "F4") { appendToken("<F4>") }
            ShortcutButton(token: "<F5>", label: "F5") { appendToken("<F5>") }
            ShortcutButton(token: "<F6>", label: "F6") { appendToken("<F6>") }

            ShortcutButton(token: "<F7>", label: "F7") { appendToken("<F7>") }
            ShortcutButton(token: "<F8>", label: "F8") { appendToken("<F8>") }
            ShortcutButton(token: "<F9>", label: "F9") { appendToken("<F9>") }
            ShortcutButton(token: "<F10>", label: "F10") { appendToken("<F10>") }
            ShortcutButton(token: "<F11>", label: "F11") { appendToken("<F11>") }

            ShortcutButton(token: "<F12>", label: "F12") { appendToken("<F12>") }

            // Modifiers
            ShortcutButton(token: "<CTRL>", label: "Ctrl") { appendToken("<CTRL>") }
            ShortcutButton(token: "<SHIFT>", label: "Shift") { appendToken("<SHIFT>") }
            ShortcutButton(token: "<ALT>", label: "Alt") { appendToken("<ALT>") }
            ShortcutButton(token: "<CMD>", label: cmdLabel) { appendToken("<\(cmdToken)>") }

            // Delays
            ShortcutButton(token: "<DELAY05S>", label: "0.5s") { appendToken("<DELAY05S>") }
            ShortcutButton(token: "<DELAY1S>", label: "1s") { appendToken("<DELAY1S>") }
            ShortcutButton(token: "<DELAY2S>", label: "2s") { appendToken("<DELAY2S>") }
            ShortcutButton(token: "<DELAY5S>", label: "5s") { appendToken("<DELAY5S>") }
            ShortcutButton(token: "<DELAY10S>", label: "10s") { appendToken("<DELAY10S>") }
        }
    }

    private var cmdLabel: String {
        switch targetSystem {
        case .macOS: return "Cmd"
        case .windows, .linux: return "Win"
        case .iOS, .android: return "Ctrl"
        }
    }

    private var cmdToken: String {
        switch targetSystem {
        case .macOS: return "CMD"
        case .windows, .linux: return "WIN"
        case .iOS, .android: return "CTRL"
        }
    }

    // MARK: - Composite Key Shortcuts

    private var compositeKeyShortcuts: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(compositeKeysForTarget, id: \.token) { combo in
                ShortcutButton(token: combo.token, label: combo.label) {
                    appendToken(combo.token)
                }
            }
        }
    }

    private var compositeKeysForTarget: [(token: String, label: String)] {
        switch targetSystem {
        case .macOS:
            return [
                ("<CMD>c</CMD>", "Cmd+C"),
                ("<CMD>v</CMD>", "Cmd+V"),
                ("<CMD>x</CMD>", "Cmd+X"),
                ("<CMD>a</CMD>", "Cmd+A"),
                ("<CMD>s</CMD>", "Cmd+S"),
                ("<CMD>z</CMD>", "Cmd+Z"),
                ("<CMD><TAB></CMD>", "Cmd+Tab"),
                ("<CMD><SPACE></CMD>", "Cmd+Space"),
                ("<CMD>q</CMD>", "Cmd+Q"),
                ("<CMD>w</CMD>", "Cmd+W"),
                ("<CMD>n</CMD>", "Cmd+N"),
                ("<CMD><SHIFT>3</SHIFT></CMD>", "Screenshot"),
            ]
        case .windows:
            return [
                ("<CTRL>c</CTRL>", "Ctrl+C"),
                ("<CTRL>v</CTRL>", "Ctrl+V"),
                ("<CTRL>x</CTRL>", "Ctrl+X"),
                ("<CTRL>a</CTRL>", "Ctrl+A"),
                ("<CTRL>s</CTRL>", "Ctrl+S"),
                ("<CTRL>z</CTRL>", "Ctrl+Z"),
                ("<ALT><TAB></ALT>", "Alt+Tab"),
                ("<CTRL><ALT><DEL></CTRL></ALT>", "Ctrl+Alt+Del"),
                ("<WIN>d</WIN>", "Win+D"),
                ("<WIN>l</WIN>", "Win+L"),
                ("<WIN>e</WIN>", "Win+E"),
                ("<CTRL><SHIFT>ESC</CTRL>", "Task Mgr"),
            ]
        case .linux:
            return [
                ("<CTRL>c</CTRL>", "Ctrl+C"),
                ("<CTRL>v</CTRL>", "Ctrl+V"),
                ("<CTRL>x</CTRL>", "Ctrl+X"),
                ("<CTRL>a</CTRL>", "Ctrl+A"),
                ("<CTRL>s</CTRL>", "Ctrl+S"),
                ("<CTRL>z</CTRL>", "Ctrl+Z"),
                ("<ALT><TAB></ALT>", "Alt+Tab"),
                ("<ALT><F2></ALT>", "Run Cmd"),
                ("<CTRL><ALT>T</CTRL>", "Terminal"),
            ]
        case .iOS:
            return [
                ("<CTRL>c</CTRL>", "Ctrl+C"),
                ("<CTRL>v</CTRL>", "Ctrl+V"),
                ("<CTRL>x</CTRL>", "Ctrl+X"),
                ("<CTRL>a</CTRL>", "Ctrl+A"),
                ("<CTRL>s</CTRL>", "Ctrl+S"),
                ("<CTRL>z</CTRL>", "Ctrl+Z"),
                ("<ALT><TAB></ALT>", "Alt+Tab"),
            ]
        case .android:
            return [
                ("<CTRL>c</CTRL>", "Ctrl+C"),
                ("<CTRL>v</CTRL>", "Ctrl+V"),
                ("<CTRL>x</CTRL>", "Ctrl+X"),
                ("<CTRL>a</CTRL>", "Ctrl+A"),
                ("<CTRL>s</CTRL>", "Ctrl+S"),
                ("<CTRL>z</CTRL>", "Ctrl+Z"),
                ("<ALT><TAB></ALT>", "Alt+Tab"),
            ]
        }
    }

    // MARK: - Macro Reference Shortcuts

    private var macroReferenceShortcuts: some View {
        Group {
            if otherMacros.isEmpty {
                Text("No other macros to reference")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                ForEach(otherMacros) { macro in
                    ShortcutButton(token: "<MACRO:\(macro.id.uuidString)>", label: macro.label) {
                        appendToken("<MACRO:\(macro.id.uuidString)>")
                    }
                }
                }
            }
        }
    }

    private var otherMacros: [Macro] {
        macroManager.macros.filter { $0.id != editingMacro?.id }
    }

    // MARK: - Actions

    private func appendToken(_ token: String) {
        if data.isEmpty {
            data = token
        } else {
            data += token
        }
    }

    private func save() {
        if let existing = editingMacro {
            var updated = existing
            updated.label = label
            updated.description = description
            updated.isVerified = isVerified
            updated.targetSystem = targetSystem
            updated.data = data
            updated.intervalMs = intervalMs
            macroManager.update(updated)
        } else {
            let macro = Macro(
                label: label,
                description: description,
                isVerified: isVerified,
                data: data,
                targetSystem: targetSystem,
                intervalMs: intervalMs
            )
            macroManager.add(macro)
        }
        dismiss()
    }

    private func delete() {
        if let existing = editingMacro {
            macroManager.delete(id: existing.id)
        }
        dismiss()
    }
}

// MARK: - Shortcut Button Component

struct ShortcutButton: View {
    let token: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(6)
        }
        .accessibilityLabel(label)
        .accessibilityHint("Insert \(token)")
    }
}

#Preview {
    Text("MacroEditorView requires KeyboardInputManager")
}
