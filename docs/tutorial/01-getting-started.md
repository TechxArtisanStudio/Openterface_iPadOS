# Tutorial 1: Getting Started

This guide covers everything from installing the app to seeing your first video feed.

## Prerequisites

- An iPad running iPadOS 17.0 or later
- An Openterface KVM dongle ([openkvmdongle.com](https://www.openkvmdongle.com/))
- A target PC connected to the Openterface dongle via USB and HDMI

## Step 1: Launch the App

Open the Openterface app on your iPad. On first launch, you will see the permission request screen.

## Step 2: Grant Permissions

The app requires several permissions to function. You must grant **Camera** and **Microphone** access to see the video feed.

| Permission | Why It's Needed | When It's Asked |
|-----------|----------------|-----------------|
| **Camera** | Display live video from the Openterface capture card | At first launch |
| **Microphone** | Capture audio from the target PC for A/V preview | At first launch |
| **Bluetooth** | Connect to the Openterface dongle for keyboard/mouse control | At first launch |
| **Photo Library** | Save screenshots and recordings to your Photos app | When you first take a screenshot or recording |

If you accidentally denied a permission, you can fix it in **Settings > Privacy & Security**.

## Step 3: Understanding the Screen

Once permissions are granted, you'll see the main interface:

```
┌─────────────────────────────────┐
│                                 │
│                                 │
│      Live Video Preview         │
│    (from target PC screen)      │
│                                 │
│                                 │
│                                 │
├─────────────────────────────────┤
│ [BLE] [Video] [Audio] [Record]  │
│ [Camera] [Keyboard] [Zoom] ...  │
└─────────────────────────────────┘
   Bottom Control Toolbar
```

- **Video Preview** fills most of the screen, showing whatever the target PC is displaying
- **Control Toolbar** sits at the bottom with all feature buttons

## Step 4: Connect via Bluetooth

To send keyboard and mouse input to the target PC, you need to connect to the Openterface dongle via Bluetooth:

1. Tap the **BLE** button (Bluetooth icon) in the toolbar
2. The Bluetooth Connection screen appears and starts scanning automatically
3. When your Openterface device appears in the list, tap **Connect**
4. The button turns green and shows the signal strength (RSSI) in dBm

> **Tip:** The app has auto-connect enabled by default. If a device named `kvm*` is found during startup, it will connect automatically.

## Step 5: Verify the Connection

Once connected:
- The BLE button in the toolbar shows a **green indicator**
- Tapping the video preview should send a **left-click** to the target PC
- Opening the floating keyboard and pressing keys should type on the target PC

## Troubleshooting

**Camera not showing?**
- Make sure the Openterface dongle is plugged into the target PC's USB port
- Check that the HDMI input is connected and displaying a signal

**Bluetooth not finding devices?**
- Make sure Bluetooth is enabled in iPad Settings
- Ensure the Openterface dongle is powered on and nearby
- Tap **Scan** in the Bluetooth Connection screen

**Can't type on the target PC?**
- Verify Bluetooth is connected (green BLE indicator)
- Check that the Openterface dongle is recognized by the target PC as a keyboard/mouse
