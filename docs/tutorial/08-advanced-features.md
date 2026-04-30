# Tutorial 8: Advanced Features

Additional tools and utilities for power users and developers.

## Info Overlay

Tap the **Info** button (info circle icon) to display the input status overlay in the top-right corner.

### What It Shows

The Info Overlay displays real-time input diagnostics:

```
┌─ Input Status ────────┐
│ ───────────────────── │
│ Mouse                 │
│ Mode: Absolute        │
│ Position: 512.0, 384.0│
│ Drag Mode: Active     │
│ Scrolling: Inactive   │
│ ───────────────────── │
│ Keyboard              │
│ Mode: Normal          │
│ Caps Lock: OFF        │
│ Modifiers: Ctrl, Shift│
│ Keys: a, b, c         │
└───────────────────────┘
```

| Field | Description |
|-------|-------------|
| **Mouse Mode** | Current mouse control mode (Absolute/iPencil or Relative/Pan) |
| **Position** | Current cursor coordinates on the target screen |
| **Drag Mode** | Whether the left mouse button is currently held down |
| **Scrolling** | Whether two-finger scroll mode is active |
| **Keyboard Mode** | Current keyboard mode (Normal or Game) |
| **Caps Lock** | Whether Caps Lock is toggled on |
| **Modifiers** | Currently held modifier keys (Ctrl, Shift, Alt, Cmd) |
| **Keys** | Currently pressed non-modifier keys |

The overlay is **transparent to touches** — it doesn't block interaction with the video preview.

## More Options

Tap the **More** button (ellipsis icon) for additional options. The advanced menu provides access to less frequently used settings and tools.

## Screen Orientation Correction

Tap the **Rotate** button in the toolbar to cycle through orientation correction modes. This corrects the video preview rotation when the Openterface dongle is mounted in a non-standard orientation.

Available modes cycle through:
- **Normal** — No rotation
- **90° clockwise** — For sideways mounting
- **180°** — For upside-down mounting
- **90° counter-clockwise** — For the other sideways mounting

This affects both the live video preview and saved screenshots/recordings.

## Idle Timer Disabled

The app keeps the iPad screen **awake** during use by disabling the idle timer. This prevents the iPad from auto-locking while you're monitoring the target PC.

## Debug Tools (Development Builds)

In `DEBUG` builds, additional diagnostic tools are available:

### Debug State Print

Call `appCoordinator.printDebugState()` in the Xcode console to dump all current state:

```
=== App State Debug ===
Bluetooth State: connected
Connected Devices: 1
Camera Authorized: true
Audio Authorized: true
Camera Session: running
Keyboard Mode: Normal
Active Modifiers: []
Mouse Select Mode: false
=====================
```

### Debug Audio Authorization

Call `appCoordinator.debugAudioAuthorization()` for detailed audio session diagnostics, including:
- Permission status
- Audio route information
- Input/output device details

### Debug Camera Start

Call `appCoordinator.debugStartCameraSession()` to force-restart the camera session.

## Logging System

The app includes a built-in `Logger` with category-based filtering. Each subsystem has its own log category:

| Category | Covers |
|----------|--------|
| `bluetooth` | BLE scanning, connection, data transmission |
| `mouse` | Mouse input, gesture detection, mode changes |
| `keyboard` | Key events, modifier state, composite keys |
| `camera` | Video recording, screenshots, photo capture |
| `ui` | Touch handling, gesture recognition, preview layer |
| `general` | App lifecycle, general info |

### Adjusting Logging

To reduce console noise, uncomment the `init()` block in `Openterface_iOSApp.swift`:

```swift
Logger.shared.disableCategory(.bluetooth)   // Quiet BLE spam
Logger.shared.setMinimumLevel(.warning)      // Warnings + errors only
Logger.shared.disableCategory(.mouse)        // Quiet mouse events
Logger.shared.setEnabled(false)              // Disable all logging
```

## Files & Locations

All user-generated files are stored in:

```
Documents/
└── Recordings/
    ├── Openterface_2025-10-21_14-30-00.jpg   (screenshot)
    ├── Openterface_2025-10-21_14-30-05.mov   (recording)
    └── ...
```

Browse these files in the **Files app** under **On My iPad > Openterface KVM > Recordings**.

## Keyboard Shortcuts Reference

Quick reference for all supported special keys on the floating keyboard:

| Key | HID Code | Key | HID Code |
|-----|----------|-----|----------|
| Enter | 0x28 | Escape | 0x29 |
| Backspace | 0x2A | Tab | 0x2B |
| Space | 0x2C | Caps Lock | 0x39 |
| Delete | 0x4C | Insert | 0x49 |
| Home | 0x4A | End | 0x4D |
| Page Up | 0x4B | Page Down | 0x4E |
| Arrow keys | 0x4F-0x52 | F1-F12 | 0x3A-0x45 |
| Ctrl | 0xE0 | Shift | 0xE1 |
| Alt | 0xE2 | Cmd | 0xE3 |
