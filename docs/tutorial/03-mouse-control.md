# Tutorial 3: Mouse Control

The Openterface app lets you control the target PC's cursor using touch gestures on the video preview. There are **two mouse modes**, each optimized for different use cases.

## Mouse Modes

Tap the **mouse mode button** to toggle between modes. The current mode is shown on the button:

| Mode | Icon | Best For |
|------|------|----------|
| **Pan Mode** (Relative) | Hand icon | General navigation, like a laptop trackpad |
| **iPencil Mode** (Absolute) | Pencil icon | Precise work with Apple Pencil or stylus |

## Pan Mode (Relative)

In Pan Mode, your finger acts like a **laptop trackpad**:

| Gesture | Action on Target PC |
|---------|-------------------|
| **Single tap** | Left-click |
| **Tap & drag** | Move cursor (relative movement) |
| **Double-tap** | Double-click |
| **Double-tap & hold** | Left-click and drag (for selecting text, moving windows) |
| **Long press** | Right-click |
| **Two-finger tap** | Right-click |
| **Two-finger drag (vertical/horizontal)** | Scroll wheel |

### How Relative Movement Works

In this mode, the cursor moves based on the **direction and distance** you drag your finger, not on the exact position. A small drag moves the cursor a little; a fast drag moves it more. Movement is clamped to -127 to +127 pixels per event.

## iPencil Mode (Absolute)

In iPencil Mode, your touch position maps **directly** to a point on the target PC's screen, like a drawing tablet:

| Gesture | Action on Target PC |
|---------|-------------------|
| **Single tap** | Move cursor to tapped point + left-click |
| **Tap & drag** | Move cursor + left button held (for dragging) |
| **Double tap** | Double-click at the tapped point |
| **Press & hold** | Right-click at the tapped point |
| **Two-finger tap** | Right-click |
| **Two-finger drag** | Scroll wheel |

### Coordinate Mapping

In iPencil Mode, touch coordinates are normalized to the **0-1 range** and mapped to the target PC's screen using a 4096x4096 coordinate space. The app uses the actual video content area (not the full screen bounds) for accurate mapping.

### Apple Pencil Support

When using an Apple Pencil in iPencil Mode, the app captures **coalesced touch events** — the intermediate touch positions between screen refreshes. This provides smooth, precise cursor movement that tracks the actual pencil path closely.

## Quick Menu (Right-Click Alternatives)

Long-press on the video preview to open a quick menu with three options:

| Option | What It Does |
|--------|-------------|
| **Left Click** | Sends a left-click at the pressed location |
| **Right Click** | Sends a right-click at the pressed location |
| **Drag** | Enters drag mode — subsequent movement drags with the left button held |
| **Cancel** | Dismisses the menu |

## Drag Mode

When in drag mode (toggled via the quick menu or double-tap & hold in relative mode):
- The left mouse button stays **held down**
- Any finger movement drags the target cursor
- A "Dragging Mode Active" label appears centered on the screen
- Double-tap or select Drag from the quick menu again to exit

## Tips

- **Pan Mode** is best for general desktop use and when your iPad is on a flat surface
- **iPencil Mode** is best when you need to point at specific UI elements or when using an Apple Pencil
- If a click doesn't register, try a slightly longer press — the gesture system has a 5px movement threshold to distinguish taps from drags
