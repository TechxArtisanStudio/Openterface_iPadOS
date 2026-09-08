//
//  FloatingKeyboardView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI
import UIKit

/// Openterface brand orange (#FF6A00) used by the shortcut strip chips.
private let shortcutOrange = Color(red: 1.0, green: 106.0 / 255.0, blue: 0.0)

struct FloatingKeyboardView: View {
    @Binding var isPresented: Bool
    @ObservedObject var keyboardManager: KeyboardInputManager
    @ObservedObject var appCoordinator: AppCoordinator
    @ObservedObject private var profileManager = ShortcutProfileManager.shared
    @State private var dragOffset = CGSize.zero
    @State private var lastDragOffset = CGSize.zero
    @State private var isDragging = false
    /// Shortcut chip currently held down (finger down, key not yet released) — used to
    /// guarantee a release when the strip pager steals the touch mid-swipe.
    @State private var activeShortcutItem: ShortcutItem? = nil
    @State private var shortcutPage: Int = 0
    @State private var shortcutDragOffset: CGFloat = 0

    /// Target OS driving keycap labels, glyphs and modifier translation.
    private var targetOS: MacroTargetSystem { appCoordinator.targetOS }

    /// Keyboard layout (last row modifiers only — arrow keys rendered as inverted-T cluster).
    /// The bottom-row GUI key label follows the target OS (Cmd / Win / Super), but every
    /// variant maps to the same HID GUI key (0x08) inside KeyboardInputManager.
    private var keyRows: [[String]] {
        let gui = targetOS.guiKeyName
        return [
            ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Del"],
            ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
            ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"],
            ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
            ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
            ["Ctrl", "Alt", gui, "Space", gui, "Alt"]
        ]
    }
    
    var body: some View {
        ZStack {
            // Floating keyboard panel (no background overlay to allow mouse interaction)
            keyboardContainer
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .offset(dragOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(true) // Allow hit testing for the keyboard itself
        .background(
            // Semi-transparent background that doesn't block interactions
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(false) // This allows touches to pass through to the underlying view
        )
    }
    
    // MARK: - Keyboard Container
    private var keyboardContainer: some View {
        VStack(spacing: 0) {
            // Header with drag handle and controls
            keyboardHeaderView

            // My Shortcuts quick-access button row (always visible above the keys)
            shortcutBarView

            // Keyboard rows
            keyboardRowsView
        }
        .frame(width: keyboardWidth + 32) // Add padding equivalent (16 points on each side)
    }
    
    // MARK: - Header View
    private var keyboardHeaderView: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Virtual Keyboard")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Mouse still active")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Target OS indicator + cycle button
            Button(action: {
                appCoordinator.cycleTargetOS()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: targetOS.sfSymbol)
                        .font(.caption)
                    Text(targetOS.displayName)
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)
            }

            // Mode indicator
            Text(keyboardManager.currentMode.description)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(4)

            // Close button
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            // Add a more opaque background to make the keyboard clearly visible
            Color.backgroundPrimary
                .opacity(0.95)
                .background(.ultraThinMaterial)
        )
        .gesture(dragGesture)
    }

    // MARK: - My Shortcuts Bar

    private var myShortcuts: [ShortcutItem] {
        profileManager.myShortcuts(for: profileManager.activeProfileId)
    }

    /// Pageable favorites strip — 7 shortcuts per page, swipe left/right to flip
    /// (mirrors KeyCmd's ShortcutStripPager). Empty favorites → standard fallback set.
    private var shortcutBarView: some View {
        let source = myShortcuts.isEmpty ? standardFallbackShortcuts : myShortcuts
        let pages = stride(from: 0, to: source.count, by: 7).map {
            Array(source[$0..<min($0 + 7, source.count)])
        }
        return Group {
            if pages.isEmpty {
                Color.clear.frame(height: 40)
            } else {
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        HStack(spacing: 0) {
                            ForEach(pages.indices, id: \.self) { pageIndex in
                                shortcutRow(pages[pageIndex])
                                    .frame(width: w)
                            }
                        }
                        .offset(x: -CGFloat(shortcutPage) * w + shortcutDragOffset)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8),
                                   value: shortcutPage)
                        .frame(width: w, alignment: .leading)
                        .clipped()
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onChanged { v in
                                    // If the strip pager steals the touch from a chip that
                                    // currently has a shortcut pressed, release it so the
                                    // target never sees a stuck key.
                                    if let stuck = activeShortcutItem {
                                        shortcutKeyUp(stuck)
                                    }
                                    shortcutDragOffset = v.translation.width
                                }
                                .onEnded { v in
                                    let threshold = w * 0.12
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        var didFlip = false
                                        if v.translation.width < -threshold,
                                           shortcutPage < pages.count - 1 {
                                            shortcutPage += 1
                                            didFlip = true
                                        } else if v.translation.width > threshold,
                                                  shortcutPage > 0 {
                                            shortcutPage -= 1
                                            didFlip = true
                                        }
                                        if didFlip {
                                            let flip = UIImpactFeedbackGenerator(style: .medium)
                                            flip.impactOccurred()
                                        }
                                        shortcutDragOffset = 0
                                    }
                                }
                        )
                    }
                    .frame(height: 40)

                    // Page indicator dots (only when more than one page)
                    if pages.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(pages.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == shortcutPage ? shortcutOrange : Color.gray.opacity(0.4))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    // The band is visually part of the panel, but touch on its empty
                    // areas (between/around chips) must pass through to the mouse-pad
                    // layer below — only the chips themselves should capture touches.
                    Color.backgroundPrimary
                        .opacity(0.95)
                        .background(.ultraThinMaterial)
                        .allowsHitTesting(false)
                )
            }
        }
        .onChange(of: profileManager.myShortcutsVersion) {
            shortcutPage = 0
        }
        .onChange(of: profileManager.activeProfileId) {
            shortcutPage = 0
        }
    }

    /// A single strip page: fixed 7 equal slots (empty trailing slots stay blank).
    private func shortcutRow(_ entries: [ShortcutItem]) -> some View {
        let slots: [ShortcutItem?] = (0..<7).map { $0 < entries.count ? entries[$0] : nil }
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                if let shortcut = slots[index] {
                    shortcutChip(shortcut)
                } else {
                    // Empty slot in the 7-slot strip page. `Color.clear` is still
                    // hit-testable in SwiftUI, so we explicitly opt it out — otherwise
                    // the entire strip width swallows mouse-drag touches that the user
                    // intends for the underlying camera preview (remote mouse).
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 0)
    }

    /// 7 standard shortcuts shown when the active profile has no "My Shortcuts" yet
    /// (mirrors KeyCmd's ShortcutStripRowView; pm follows the target OS so Copy on
    /// Windows/Linux becomes Ctrl+C rather than the GUI key).
    private var standardFallbackShortcuts: [ShortcutItem] {
        let pm = targetOS.primaryModifier
        func item(_ description: String, _ key: String, _ modifiers: [String]) -> ShortcutItem {
            ShortcutItem(
                description: description,
                key: key,
                modifier: modifiers.isEmpty ? nil : modifiers.joined(separator: "+"),
                keyCode: key
            )
        }
        return [
            item("Select All", "A", [pm]),
            item("Copy", "C", [pm]),
            item("Cut", "X", [pm]),
            item("Paste", "V", [pm]),
            item("Save", "S", [pm]),
            item("Undo", "Z", [pm]),
            item("Find", "F", ["Ctrl"])
        ]
    }

    private func shortcutChip(_ shortcut: ShortcutItem) -> some View {
        ShortcutChipView(
            shortcut: shortcut,
            chordLabel: chordText(for: shortcut),
            onPress: { shortcutKeyDown(shortcut) },
            onRelease: { shortcutKeyUp(shortcut) }
        )
    }

    /// Chip that behaves like a real keyboard key: touch-down fires the key-press
    /// (half) and touch-up fires the release (half), so the target never sees a
    /// stuck key and holding the chip keeps the key held down (OS-level repeat).
    private struct ShortcutChipView: View {
        let shortcut: ShortcutItem
        let chordLabel: String
        let onPress: () -> Void
        let onRelease: () -> Void

        @State private var isPressed = false

        var body: some View {
            HStack(spacing: 3) {
                Text(chordLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(shortcut.description)
                    .font(.system(size: 8, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // First onChanged is the touch-down moment.
                        guard !isPressed else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            isPressed = true
                        }
                        // Haptic fires the instant the finger touches down.
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        onPress()
                    }
                    .onEnded { _ in
                        withAnimation(.easeIn(duration: 0.12)) {
                            isPressed = false
                        }
                        onRelease()
                    }
            )
        }

        private var foregroundColor: Color {
            isPressed ? .white : shortcutOrange
        }

        private var backgroundColor: Color {
            isPressed ? shortcutOrange : shortcutOrange.opacity(0.14)
        }
    }

    /// Converts a modifier name into a glyph. macOS uses ⌘⌃⌥⇧; non-Mac targets use plain
    /// text ("Ctrl"/"Alt"/"Shift") — mirrors KeyCmd's ShortcutPanel formatComboText.
    private func glyph(for modifier: String) -> String {
        let m = modifier.trimmingCharacters(in: .whitespaces).lowercased()
        if targetOS.isMacStyle {
            switch m {
            case "cmd", "command", "win", "super", "meta": return "⌘"
            case "ctrl", "control": return "⌃"
            case "shift": return "⇧"
            case "alt", "option": return "⌥"
            default: return modifier
            }
        } else {
            // Non-macOS: plain modifier text (already translated by chordText).
            switch m {
            case "cmd", "command", "meta": return "Ctrl" // semantic Cmd → Ctrl translation
            case "win": return "Win"
            case "super": return "Super"
            case "ctrl", "control": return "Ctrl"
            case "shift": return "Shift"
            case "alt", "option": return "Alt"
            default: return modifier
            }
        }
    }

    /// KeyCmd-aligned combo text. Translates modifiers to target-OS semantics FIRST so the
    /// label always matches what is actually sent: macOS joins glyphs (⌘⇧C);
    /// others join with "+" (Ctrl+C).
    private func chordText(for shortcut: ShortcutItem) -> String {
        guard let mod = shortcut.modifier, !mod.isEmpty else {
            return shortcut.key
        }
        let parts = mod.components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let translated = ModifierTranslator.translate(parts, for: targetOS)
        let glyphs = translated.map { glyph(for: $0) }
        if targetOS.isMacStyle {
            return glyphs.joined() + shortcut.key
        } else {
            return glyphs.joined(separator: "+") + "+" + shortcut.key
        }
    }

    // MARK: - Shortcut Press/Release (real key semantics)
    // Strip chips behave like actual keyboard keys: touch-down sends the press half,
    // touch-up sends the release half (the target can keep a direction key held and
    // repeat). Modifiers are translated to target-OS semantics first (Cmd → Ctrl on
    // non-Mac), matching the label that chordText(for:) shows.

    /// Resolves a shortcut into (translated modifiers, main key).
    /// - Returns: nil when the item is a plain single key with no modifiers.
    private func shortcutChord(_ shortcut: ShortcutItem) -> (modifiers: [String], key: String)? {
        if let modifier = shortcut.modifier, !modifier.isEmpty {
            let mods = modifier.components(separatedBy: "+")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return (ModifierTranslator.translate(mods, for: targetOS), shortcut.keyCode)
        }
        if shortcut.keyCode.contains("+") {
            let parts = shortcut.keyCode.components(separatedBy: "+")
            if parts.count >= 2, let key = parts.last {
                return (ModifierTranslator.translate(Array(parts.dropLast()), for: targetOS), key)
            }
        }
        return nil
    }

    /// Touch-down half: mark this item as the active held shortcut and send only the
    /// press (chords via handleChordPress, plain keys via handleKeyPress).
    private func shortcutKeyDown(_ shortcut: ShortcutItem) {
        activeShortcutItem = shortcut
        if let chord = shortcutChord(shortcut) {
            keyboardManager.handleChordPress(modifiers: chord.modifiers, key: chord.key)
        } else {
            keyboardManager.handleKeyPress(shortcut.keyCode)
        }
    }

    /// Touch-up half: clear the active held shortcut and send the release.
    private func shortcutKeyUp(_ shortcut: ShortcutItem) {
        if activeShortcutItem?.id == shortcut.id {
            activeShortcutItem = nil
        }
        if let chord = shortcutChord(shortcut) {
            keyboardManager.handleChordRelease()
        } else {
            keyboardManager.handleKeyRelease(shortcut.keyCode)
        }
    }
    
    // MARK: - Keyboard Rows View
    private var keyboardRowsView: some View {
        VStack(spacing: 4) {
            ForEach(Array(keyRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { key in
                        makeKeyButton(for: key, in: rowIndex)
                    }

                    // Add inverted-T arrow cluster to the last row
                    if rowIndex == keyRows.count - 1 {
                        arrowKeyCluster
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            // Add a more opaque background to make the keyboard clearly visible
            Color.backgroundSecondary
                .opacity(0.95)
                .background(.ultraThinMaterial)
        )
    }

    // MARK: - Arrow Key Cluster (inverted-T layout with equal-sized keys)
    private var arrowKeyCluster: some View {
        let arrowWidth = keyWidth(for: "Left", in: keyRows.count - 1) // 40
        let keyHeight: CGFloat = 36

        // `Color.clear` placeholders are hit-testable in SwiftUI by default — opt them
        // out so the invisible areas around the inverted-T cluster pass touches through
        // to the mouse-pad layer below.
        let placeholder = Color.clear
            .frame(width: arrowWidth, height: keyHeight)
            .allowsHitTesting(false)

        return VStack(spacing: 2) {
            // Top row: placeholder + Up + placeholder (so Up is centered above Down)
            HStack(spacing: 2) {
                placeholder
                makeArrowKey("Up", width: arrowWidth)
                placeholder
            }
            // Bottom row: Left, Down, Right
            HStack(spacing: 2) {
                makeArrowKey("Left", width: arrowWidth)
                makeArrowKey("Down", width: arrowWidth)
                makeArrowKey("Right", width: arrowWidth)
            }
        }
    }

    // MARK: - Arrow Key Factory
    private func makeArrowKey(_ key: String, width: CGFloat) -> KeyButton {
        KeyButton(
            key: key,
            displayValue: getDisplayValue(for: key),
            width: width,
            isPressed: keyboardManager.pressedKeys.contains(key),
            isModifier: false,
            isModifierActive: false,
            onPress: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                self.keyboardManager.handleKeyPress(key)
            },
            onRelease: {
                self.keyboardManager.handleKeyRelease(key)
            }
        )
    }

    // MARK: - Key Button Factory
    private func makeKeyButton(for key: String, in row: Int) -> KeyButton {
        KeyButton(
            key: key,
            displayValue: getDisplayValue(for: key),
            width: keyWidth(for: key, in: row),
            isPressed: keyboardManager.pressedKeys.contains(key),
            isModifier: isModifierKey(key),
            isModifierActive: isModifierActive(key),
            onPress: {
                // Add haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()

                if self.isModifierKey(key) {
                    self.handleKeyPress(key)
                } else {
                    self.keyboardManager.handleKeyPress(key)
                }
            },
            onRelease: {
                if !self.isModifierKey(key) {
                    self.keyboardManager.handleKeyRelease(key)
                }
            }
        )
    }
    
    // MARK: - Computed Properties
    private var keyboardWidth: CGFloat {
        let rowWidths = keyRows.enumerated().map { rowIndex, row in
            let keyWidths = row.map { keyWidth(for: $0, in: rowIndex) }
            let spacing = CGFloat(row.count - 1) * 2
            return keyWidths.reduce(0, +) + spacing
        }
        return rowWidths.max() ?? 400
    }

    /// Total keyboard height: header + shortcut bar + key rows + padding.
    private var keyboardHeight: CGFloat {
        let keyHeight: CGFloat = 36
        let keyRowSpacing: CGFloat = 4
        let rowsHeight = CGFloat(keyRows.count) * keyHeight
            + CGFloat(keyRows.count - 1) * keyRowSpacing
            + 16 + 16 // vertical padding on keyboardRowsView
        let headerHeight: CGFloat = 8 + 8 + 40 // vertical padding + title/subtitle content
        let barHeight: CGFloat = 6 + 6 + 40 // bar padding + fixed frame height
        return headerHeight + barHeight + rowsHeight
    }
    
    // MARK: - Draggable
    // The keyboard sits inside a full-screen ZStack at .center with .offset(dragOffset),
    // so offset(0,0) == centered. Keep a persistent "last settled" offset and add the
    // per-gesture translation on top of it — otherwise every drag snaps back to center
    // before following the finger.
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                withAnimation(.none) {
                    dragOffset = CGSize(
                        width: lastDragOffset.width + value.translation.width,
                        height: lastDragOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                isDragging = false
                dragOffset = CGSize(
                    width: lastDragOffset.width + value.translation.width,
                    height: lastDragOffset.height + value.translation.height
                )
                constrainToScreen()
            }
    }
    
    // MARK: - Helper Methods
    private func keyWidth(for key: String, in row: Int) -> CGFloat {
        switch key {
        case "Space": return 180
        case "Shift": return row == 4 ? 80 : 60
        case "Backspace", "Enter": return 80
        case "Tab", "Caps": return 70
        case "Ctrl", "Alt", "Cmd", "Win", "Super", "Del": return 50
        case "\\": return 60
        case "Left", "Up", "Down", "Right": return 40
        default: return 40
        }
    }
    
    private func getDisplayValue(for key: String) -> String {
        let specialKeys = ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Del",
                          "Tab", "Caps", "Enter", "Shift", "Ctrl", "Alt", "Cmd", "Win", "Super", "Space", "Backspace", "\\",
                          "Left", "Up", "Down", "Right"]
        
        if specialKeys.contains(key) {
            return key.keyDisplayName
        }
        
        let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
        let isCapsActive = keyboardManager.capsLockActive
        
        // For letters
        if key.count == 1 && key.first!.isLetter {
            let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
            return shouldBeUppercase ? key.uppercased() : key.lowercased()
        }
        
        // For numbers and symbols with shift variants
        if isShiftActive {
            let shiftMap: [String: String] = [
                "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
                "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
                "-": "_", "=": "+", "[": "{", "]": "}",
                ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"
            ]
            return shiftMap[key] ?? key
        }
        
        return key
    }
    
    private func isModifierKey(_ key: String) -> Bool {
        return key.isModifierKey
    }
    
    private func isModifierActive(_ key: String) -> Bool {
        if key == "Caps" {
            return keyboardManager.capsLockActive
        }
        return keyboardManager.activeModifiers.contains(key)
    }
    
    private func handleKeyPress(_ key: String) {
        if isModifierKey(key) {
            if key == "Caps" {
                keyboardManager.handleKeyPress(key)
            } else {
                keyboardManager.handleModifierToggle(key)
            }
        }
        // For regular keys, handleKeyPress is called directly in onPress
    }
    
    private func constrainToScreen() {
        let screenSize = UIScreen.main.bounds.size
        let keyboardSize = CGSize(width: keyboardWidth + 40, height: keyboardHeight)

        let maxX = (screenSize.width - keyboardSize.width) / 2
        let maxY = (screenSize.height - keyboardSize.height) / 2

        let constrainedX = max(-maxX, min(maxX, dragOffset.width))
        let constrainedY = max(-maxY, min(maxY, dragOffset.height))

        let constrained = CGSize(width: constrainedX, height: constrainedY)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = constrained
        }
        // Persist the settled position so the next drag continues from here
        // instead of resetting to center.
        lastDragOffset = constrained
    }
}

// MARK: - Key Button
struct KeyButton: View {
    let key: String
    let displayValue: String
    let width: CGFloat
    let isPressed: Bool
    let isModifier: Bool
    let isModifierActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    @State private var isButtonPressed = false
    
    private var keyHeight: CGFloat { 36 }
    
    private var fontSize: CGFloat {
        switch key {
        case "Space": return 12
        case "Backspace", "Enter", "Shift", "Tab", "Caps", "Del", "Super": return 10
        case "Ctrl", "Alt", "Cmd", "Win": return 9
        default: return 14
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(buttonColor)
                .frame(width: width, height: keyHeight)
            
            Text(displayValue)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(buttonTextColor)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isButtonPressed {
                        isButtonPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    if isButtonPressed {
                        isButtonPressed = false
                        onRelease()
                    }
                }
        )
    }
    
    private var buttonColor: Color {
        if isButtonPressed || isPressed {
            return isModifier ? (isModifierActive ? Color.blue.opacity(0.8) : Color.gray.opacity(0.6)) : Color.blue.opacity(0.6)
        } else {
            return isModifier ? (isModifierActive ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2)) : Color.gray.opacity(0.1)
        }
    }
    
    private var buttonTextColor: Color {
        if isButtonPressed || isPressed {
            return .white
        } else {
            return .primary
        }
    }
}

#Preview {
    FloatingKeyboardView(
        isPresented: .constant(true),
        keyboardManager: KeyboardInputManager(connectionManager: BluetoothConnectionManager()),
        appCoordinator: AppCoordinator()
    )
}
