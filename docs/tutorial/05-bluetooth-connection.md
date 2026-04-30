# Tutorial 5: Bluetooth Connection

The Bluetooth connection is the bridge between your iPad and the Openterface dongle. It carries all keyboard and mouse HID packets.

## Opening the Bluetooth Screen

Tap the **BLE** button in the toolbar. This opens a sheet with Bluetooth connection management.

## Scanning for Devices

When the Bluetooth screen opens, the app **automatically starts scanning** for nearby devices.

### What to Look For

The app searches for devices whose name starts with **"kvm"** (case-insensitive). Only Openterface devices will appear in the list.

### Device List

Each discovered device shows:
- **Device name** (e.g., `kvm-001`)
- **Signal strength** (RSSI in dBm) with a color-coded indicator
- **Connection status** (a green dot + "Connected" label if already connected)

| RSSI Range | Signal | Color |
|-----------|--------|-------|
| -50 to 0 dBm | Excellent | Green |
| -70 to -50 dBm | Good | Orange |
| Below -70 dBm | Fair/Poor | Red |

## Connecting

1. Find your Openterface device in the list
2. Tap **Connect** next to its name
3. The app discovers the device's BLE services and characteristics
4. Once connected, the device shows a green background with a "Connected" status
5. Signal strength monitoring starts (RSSI updates every 2 seconds)

## Auto-Connect

Auto-connect is **enabled by default**:

- **On startup**: If the app discovers a `kvm*` device during the initial 5-second scan window, it automatically connects to the device with the strongest signal
- **After disconnection**: If the device disconnects unexpectedly, the app attempts to reconnect up to **3 times** with a 2-second delay between attempts
- **Best device selection**: When multiple devices are found, the app waits 2 seconds and then connects to the one with the highest RSSI

### Disabling Auto-Connect

You can disable auto-connect if you prefer to connect manually each time. When disabled, the app scans but never auto-connects.

## Monitoring Connection Quality

After connecting, the app continuously monitors the Bluetooth signal:

- **RSSI updates** every 2 seconds
- The BLE button in the toolbar shows:
  - **Green icon** = connected
  - **RSSI value** (e.g., `-45 dBm`) replaces the "BLE" label
  - **Colored indicator** beneath the icon (green/orange/red)

## Connection States

The Bluetooth screen shows the current state of the Bluetooth system:

| State | Icon | Meaning |
|-------|------|---------|
| **Powered On** | Bluetooth icon | Bluetooth is ready |
| **Powered Off** | Bluetooth slash | Turn on Bluetooth in Settings |
| **Unauthorized** | Exclamation mark | Grant Bluetooth permission in Settings |

## Reconnection

If the connection drops unexpectedly:

1. The app attempts to reconnect to the same device (up to 3 attempts)
2. If reconnection fails, it falls back to scanning for available devices
3. Auto-connect resumes scanning if it was previously enabled

## Disconnecting

To disconnect:
1. Open the Bluetooth screen
2. Tap **Disconnect** next to the connected device
3. The connection is terminated cleanly

## Troubleshooting

**Scanning but no devices found?**
- Make sure the Openterface dongle is powered on
- Bring the iPad closer to the dongle
- Try tapping **Refresh** to restart the scan

**Connect button does nothing?**
- Check the Bluetooth state indicator at the top
- If it shows "Powered Off" or "Unauthorized", fix the Bluetooth setting first
- Tap **Open Bluetooth Settings** if prompted

**Connection keeps dropping?**
- Check the RSSI — if it's below -70 dBm, the signal is weak
- Move closer to the Openterface dongle
- Check for interference from other wireless devices
