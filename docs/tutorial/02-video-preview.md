# Tutorial 2: Video Preview

This guide covers everything you can do with the live video feed from the target PC.

## Resolution Switching

Tap the **Video** button (video icon showing current resolution) to open the resolution menu. Choose from:

| Resolution | Use Case |
|-----------|----------|
| **2160p (4K)** | Highest quality, best for detail work |
| **1080p** | Default, good balance of quality and performance |
| **720p** | Lower bandwidth, good on slower connections |
| **480p** | Lowest bandwidth, for troubleshooting |

The current resolution is displayed as a label beneath the video button.

## Zoom Mode

Tap the **Zoom** button to enter zoom mode. This enables several new interactions:

### Pinch to Zoom

With Zoom mode active, **pinch with two fingers** on the video preview to zoom in. A zoom indicator appears in the top-right corner showing the current zoom level (e.g., `2.5x`).

### Pan the View

When zoomed in, you can navigate the enlarged view:

| Gesture | Action |
|---------|--------|
| **Single finger drag** | Pan the viewport |
| **Two-finger drag** | Pan the viewport (in zoom mode) |
| **Tap** | Move viewport to center on tapped location |
| **Three-finger drag** | Pan the viewport |

### Zoom Indicator

When zoomed in, a small badge appears showing:
- The current zoom factor (e.g., `1.5x`)
- A pan hint ("3 fingers to pan")

Tapping **Zoom** again exits zoom mode and returns to the full, unzoomed view.

## Fullscreen Mode

Tap the **Fullscreen** button to hide the bottom control toolbar and extend the video preview to fill the entire screen, including the status bar area.

To exit fullscreen:
- Tap the **arrow button** in the top-left corner
- The control toolbar reappears

## Screen Rotation

The Openterface capture card may be mounted in different orientations. Tap the **Rotate** button to cycle through orientation correction modes. This rotates the video preview to match the physical orientation of the capture card.

## Mouse Interactions in Video Preview

In normal (non-zoom) mode, interactions on the video preview are mapped to mouse events on the target PC. See [Tutorial 3: Mouse Control](03-mouse-control.md) for details.

## Camera and Audio Status

When the camera is starting, a loading indicator appears with the text **"Starting Camera..."**. If there's an error, an error message is displayed with details.

When no Openterface camera is connected but permissions are granted, a guide image is shown instead of a black screen.
