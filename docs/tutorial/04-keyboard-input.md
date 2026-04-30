# Tutorial 4: Keyboard Input

Type on the target PC using either the on-screen floating keyboard or a physical iPad keyboard connected to your iPad.

## Floating Keyboard

Tap the **Keyboard** button in the toolbar to show the floating on-screen keyboard.

### Keyboard Layout

The virtual keyboard follows a standard Mac-style layout with six rows:

```
[Esc] [F1] [F2] [F3] ... [F12] [Del]
[`]  [1]  [2]  [3]  ... [0]  [-]  [=]  [Backspace]
[Tab] [q] [w] [e] ... [p]  [[]] []]  [\]
[Caps] [a] [s] [d] ... [l]  [;]  [']  [Enter]
[Shift] [z] [x] [c] ... [.]  [/]  [Shift]
[Ctrl] [Alt] [Cmd] [Space] [Cmd] [Alt] [Ctrl]
```

### Using the Keyboard

| Action | How |
|--------|-----|
| **Type a character** | Tap the key once |
| **Toggle a modifier** | Tap Ctrl, Shift, Alt, Cmd, or Caps to toggle it on/off |
| **Type uppercase** | Toggle Shift or Caps first, then tap the letter |
| **Type shifted symbols** | Toggle Shift, then tap a number key (e.g., Shift+1 = !) |
| **Close the keyboard** | Tap the **X** button in the keyboard header |

### Dragging the Keyboard

Grab the **drag handle** (three horizontal lines) in the keyboard header and drag to reposition it anywhere on screen. The keyboard stays within the screen bounds.

The header also shows:
- The current keyboard mode (Normal / Game)
- A "Mouse still active" reminder so you know tapping the video still works

### Visual Feedback

- **Pressed keys** highlight in blue
- **Active modifiers** stay highlighted (blue) until toggled off
- **Caps Lock** shows as active with a distinct color
- Keys display uppercase/lowercase and shift variants based on the current modifier state

## External iPad Keyboard

If you have a physical keyboard connected to your iPad (via Bluetooth or Smart Connector), its key presses are passed through to the target PC.

The app detects external keyboard input and handles it differently from the on-screen keyboard:
- **Modifier keys** (Ctrl, Shift, Alt, Cmd) are sent as press/release events (not toggled)
- Regular keys are sent with their active modifier state included

This means you can use combinations like `Ctrl+C` or `Alt+Tab` directly from your iPad keyboard.

## Keyboard Modes

The keyboard supports two modes:

| Mode | Description |
|------|-------------|
| **Normal** | Standard typing — modifier keys toggle on/off for on-screen use |
| **Game** | Optimized for game input; uses a different HID packet header |

The current mode is shown as a badge on the floating keyboard header.

## Composite Key Shortcuts

The app includes a library of common keyboard shortcuts organized by category. These are sent as modifier+key combinations:

### Navigation
- `Ctrl+C` / `Ctrl+V` / `Ctrl+X` — Copy, Paste, Cut
- `Ctrl+A` — Select All
- `Ctrl+F` — Find
- `Ctrl+G` — Go to Line
- `Ctrl+Home` / `Ctrl+End` — Jump to beginning/end
- `Page Up` / `Page Down` — Scroll pages

### Editing
- `Ctrl+Z` / `Ctrl+Y` — Undo / Redo
- `Ctrl+B` / `Ctrl+I` / `Ctrl+U` — Bold, Italic, Underline
- `Ctrl+D` — Duplicate line

### System
- `Ctrl+S` — Save
- `Ctrl+O` — Open File
- `Ctrl+P` — Print
- `Ctrl+R` — Refresh
- `F11` — Toggle Full Screen
- `Alt+F4` — Quit Application

### Application
- `Alt+Tab` — Switch Application
- `Cmd+M` — Minimize Window
- `Cmd+Shift+3` — Screenshot (macOS)
- `Cmd+Shift+4` — Partial Screenshot (macOS)

> **Note:** The composite key library includes both Windows (Ctrl-based) and macOS (Cmd-based) shortcuts. Use whichever matches the target PC's operating system.
