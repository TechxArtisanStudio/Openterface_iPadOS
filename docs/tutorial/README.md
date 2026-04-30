# Openterface iPadOS Tutorial

Welcome! This guide walks you through every feature of the Openterface iPadOS app, from first launch to advanced usage.

## Table of Contents

| Tutorial | What You'll Learn |
|----------|------------------|
| [01 - Getting Started](01-getting-started.md) | First launch, permissions, Bluetooth pairing, basic layout |
| [02 - Video Preview](02-video-preview.md) | Resolution switching, zoom, panning, fullscreen, rotation |
| [03 - Mouse Control](03-mouse-control.md) | Pan mode vs iPencil mode, tap/click/drag/scroll gestures |
| [04 - Keyboard Input](04-keyboard-input.md) | Floating keyboard, external keyboard, shortcut keys |
| [05 - Bluetooth Connection](05-bluetooth-connection.md) | Scanning, connecting, signal strength, auto-reconnect |
| [06 - Recording & Screenshots](06-recording-screenshots.md) | Capturing screenshots, recording video, where files are saved |
| [07 - Audio Monitoring](07-audio-monitoring.md) | Listening to the target PC's audio through your iPad |
| [08 - Advanced Features](08-advanced-features.md) | Info overlay, more options menu, debug tools |

## Quick Start

If you just want to get up and running fast:

1. **Plug in** your Openterface KVM dongle to the target PC
2. **Open the app** on your iPad and grant camera + microphone permissions
3. **Tap the BLE button** in the toolbar to scan and connect to your Openterface device
4. **Tap the video preview** to send mouse clicks, or open the **floating keyboard** to type

## Architecture at a Glance

The app has three main subsystems that work together:

```
Video Pipeline          Input Pipeline          Connection
────────────────        ──────────────          ──────────
Camera Session ──►      Touch Events ──►        BLE (FFF2)
Video Manager           HID Input Manager       Characteristic
Audio Manager           Mouse/Keyboard          Openterface
Recording Manager       Managers                Dongle
```

- **Video**: Captures the target PC's screen via the Openterface USB capture card
- **Input**: Translates your iPad touches/keystrokes into HID packets sent over Bluetooth
- **Bluetooth**: Connects to the Openterface device for keyboard/mouse injection
