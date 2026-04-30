# Openterface iPadOS

An iPadOS companion app for the [Openterface](https://www.openkvmdongle.com/) KVM dongle — remotely control your PC from your iPad with live video capture, Bluetooth HID input injection, and full keyboard/mouse emulation.

![Platform](https://img.shields.io/badge/platform-iPadOS%20%7C%20iOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

| Category | Capabilities |
|----------|-------------|
| **Video** | Live camera preview from Openterface device, resolution switching, zoom mode, full-screen mode |
| **Mouse** | Two control modes — **relative** (trackpad-like panning) and **absolute** (Apple Pencil / stylus with 4096x4096 coordinate space) |
| **Keyboard** | On-screen floating keyboard with composite key support (Ctrl+Alt+Del, shortcuts), external keyboard passthrough |
| **Bluetooth** | BLE device discovery, connection management, RSSI signal strength indicator |
| **Recording** | Screen capture screenshots and video recordings, saved to Documents or Photo Library |
| **Audio** | Audio capture and monitoring from the Openterface device |

## Architecture

```
Openterface_iOSApp
└── AppCoordinator (ObservableObject)
    ├── BluetoothConnectionManager   → BLE scanning, pairing, data transport
    ├── CameraSessionManager         → AVFoundation session orchestration
    │   ├── VideoManager             → Video preview layer & resolution
    │   ├── AudioManager           → Audio capture session
    │   └── RecordingManager         → Screenshot & video recording
    ├── HIDInputManager              → HID packet construction & routing
    │   ├── MouseInputManager        → Relative / absolute mouse control
    │   └── KeyboardInputManager     → Key event encoding & dispatch
    │       └── CompositeKeyInputManager  → Multi-key shortcut handling
    └── UI Components
        ├── MainContentView          → Root layout & authorization flow
        ├── CameraPreviewView        → Video display & touch/mouse input
        ├── ControlsView             → Toolbar with action buttons
        ├── FloatingKeyboardView     → Draggable on-screen keyboard
        ├── InfoOverlayView          → Mouse/keyboard status overlay
        └── BluetoothConnectionView  → Device pairing UI
```

## Requirements

- iPadOS 17.0+ / iOS 17.0+
- Xcode 15.0+
- Swift 6.0+
- An Openterface KVM dongle (for full functionality)

## Getting Started

### 1. Clone

```bash
git clone https://github.com/TechxArtisan/Openterface_iPadOS.git
cd Openterface_iPadOS
```

### 2. Open in Xcode

```bash
open Openterface.xcodeproj
```

### 3. Build & Run

Select the **Openterface_iOS** scheme and target your iPad or simulator, then press **Cmd+R**.

> **Simulator note:** A `SimulatorCameraMock` is included so the app runs in the simulator without a physical Openterface device attached. Bluetooth and HID features require real hardware.

## Permissions

The app requests the following permissions at runtime:

| Permission | Purpose |
|------------|---------|
| **Camera** | Display live video feed from the Openterface device |
| **Microphone** | Capture audio from the Openterface device for A/V preview |
| **Bluetooth** | Connect to and communicate with the Openterface dongle |
| **Photo Library** | Save screenshots and video recordings |

## Usage

### Mouse Modes

Tap the mouse mode button to toggle between:

- **Pan Mode (Relative)** — Drag gestures move the cursor relative to its current position, similar to a laptop trackpad.
- **iPencil Mode (Absolute)** — Touch or stylus position maps directly to a point on the remote screen, similar to a drawing tablet.

### Keyboard

- Tap the keyboard icon to show the **floating keyboard** for on-screen key input.
- Connect an external iPad keyboard for direct key passthrough via `ExternalKeyboardHandler`.

### Recording & Screenshots

Use the controls toolbar to capture screenshots or start/stop video recording. Files are saved to `Documents/Recordings/` and optionally to the Photo Library.

## Development

### Logging

The app includes a built-in `Logger` with category-based filtering. To adjust logging, uncomment the `init()` block in `Openterface_iOSApp.swift`:

```swift
Logger.shared.disableCategory(.bluetooth)   // Quiet BLE spam
Logger.shared.setMinimumLevel(.warning)      // Warnings + errors only
Logger.shared.setEnabled(false)              // Disable all logging
```

### Debug State

In `DEBUG` builds, call `appCoordinator.printDebugState()` in the console to dump the current state of all managers (Bluetooth, camera, keyboard, mouse).

## Project Structure

```
Openterface_iOS/
├── Core/
│   ├── AppCoordinator.swift           # Central state management
│   ├── Models/                        # Data models (Camera, Connection, Input)
│   └── Protocols/                     # Protocol abstractions
├── Features/
│   ├── Bluetooth/                     # BLE connection handling
│   ├── Camera/                        # AVFoundation managers
│   ├── Input/                         # HID, keyboard, mouse input
│   └── UI/
│       ├── Components/                # Reusable SwiftUI views
│       └── Screens/                   # Top-level screen views
├── Shared/
│   ├── Extensions/                    # Swift type extensions
│   └── Utils/                         # Helpers (HID, keyboard, logging)
├── Assets.xcassets/                   # App icons, colors, images
└── Preview Content/                   # SwiftUI preview assets
```

## License

MIT

## Contributing

Pull requests welcome. For major changes, please open an issue first to discuss what you would like to change.
