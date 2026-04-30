# Tutorial 7: Audio Monitoring

Listen to the target PC's audio output through your iPad's speakers or headphones.

## What Is Audio Monitoring?

Audio monitoring captures the audio stream coming from the Openterface device (which is fed by the target PC's audio output) and plays it through your iPad. This lets you **hear what the target PC hears** — useful for:

- Verifying the target PC's audio is working
- Listening to system sounds or media
- Monitoring audio during presentations or recordings

## Enabling Audio Monitoring

### Option 1: Audio Button in Toolbar

Tap the **Audio** button (speaker icon) in the toolbar:

| Icon State | Meaning |
|-----------|---------|
| Speaker with slash (gray) | Audio not authorized |
| Speaker with slash (red) | Audio monitoring is OFF |
| Speaker with waves (green) | Audio monitoring is ON |

### Option 2: On First Launch

If you haven't granted microphone permission, tapping the Audio button will prompt you to request it.

## How It Works

When audio monitoring is enabled:

1. The app sets up an `AVAudioEngine` that connects the Openterface's audio input to the iPad's audio output
2. Audio plays through the iPad's speakers or connected headphones/Bluetooth audio
3. A volume-controlled mixer node allows instant mute/unmute without stopping the engine

## Audio During Recording

When you start a video recording:
- Audio monitoring is **temporarily muted** (volume lowered to zero) to prevent feedback
- The target PC's audio is still **captured into the recording**
- After the recording stabilizes (~3 seconds), volume fades back to normal gradually

## Authorization Status

The app tracks audio authorization separately from camera authorization:

- If audio is **not authorized**, the Audio button shows a red slashed speaker
- Tapping it requests microphone permission
- Once authorized but monitoring is off, it shows a gray slashed speaker
- When monitoring is active, it shows a green speaker with waves

## Troubleshooting

**No audio playing through the iPad?**
- Check the Audio button — it should show a green speaker icon
- Make sure the Openterface device is sending audio (target PC audio output connected)
- Check iPad volume is not muted

**Audio permission denied?**
- Go to **Settings > Privacy & Security > Microphone** and enable it for the Openterface app
- Return to the app and tap the Audio button again

**Audio drops during recording?**
- This is intentional — the monitoring audio is muted during recording to prevent feedback loops, but the audio is still captured in the video file
