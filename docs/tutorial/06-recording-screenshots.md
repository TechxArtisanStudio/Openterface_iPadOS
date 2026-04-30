# Tutorial 6: Recording & Screenshots

Capture what's on the target PC's screen and save it to your iPad.

## Taking Screenshots

Tap the **Screenshot** button (camera icon) in the toolbar.

### How It Works

1. The app captures a high-resolution frame from the camera session
2. The image is corrected for orientation (applying any rotation correction you've set)
3. The screenshot is saved as a JPEG file

### Where Screenshots Go

Screenshots are saved to **two locations** (depending on settings):

| Location | Path | How to Access |
|----------|------|--------------|
| **App Documents** | `Documents/Recordings/` | Files app > On My iPad > Openterface KVM > Recordings |
| **Photos App** | Camera Roll | Photos app (if permission is granted) |

File names follow the pattern: `Openterface_YYYY-MM-DD_HH-mm-ss.jpg`

> **Note:** On first screenshot, the app requests Photo Library permission. If you deny it, screenshots still save to the Documents folder. You can enable Photo Library saving later in Settings.

## Recording Video

Tap the **Record** button (record circle icon) in the toolbar to start recording.

### Starting a Recording

1. Tap the Record button — the button highlights to show recording is active
2. The app sets up an H.264 video encoder and begins capturing frames at 30fps
3. If audio is available, the audio stream is captured simultaneously

### Stopping a Recording

Tap the **Record** button again to stop. After processing, the app displays the recording details:
- File name
- Duration (formatted, e.g., `0m 15s`)
- File size (e.g., `12.4 MB`)

### Recording Details

| Setting | Value |
|---------|-------|
| **Video codec** | H.264 |
| **Frame rate** | 30 fps |
| **Resolution** | Matches the capture device (typically 1920x1080) |
| **Audio codec** | AAC at 128 kbps, 48 kHz, stereo |
| **Container** | MOV |

### Where Recordings Go

Like screenshots, recordings are saved to:

- **App Documents**: `Documents/Recordings/Openterface_YYYY-MM-DD_HH-mm-ss.mov`
- **Photos App**: If the "save to Photo Library" setting is enabled and permission is granted

File names follow the pattern: `Openterface_YYYY-MM-DD_HH-mm-ss.mov`

## Simulator Support

When running in the iOS Simulator:
- Screenshots generate a placeholder image with the current timestamp
- Recordings create a short test video file with a solid color pattern
- These features let you test the UI flow without actual hardware

## Tips

- **Check your recording**: After stopping, the duration and size confirm the file was created successfully
- **File access**: Use the Files app to browse, share, or AirDrop your recordings
- **Storage management**: Recordings accumulate in the Documents folder. Periodically clean up old files via the Files app
