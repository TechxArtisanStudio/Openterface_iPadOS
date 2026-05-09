//
//  VideoSettingsView.swift
//  Openterface_iOS
//
//  Created by Refactor on 10/20/25.
//

import SwiftUI
import AVFoundation

public struct VideoSettingsView: View {
    @ObservedObject var cameraManager: CameraSessionManager
    @Binding var isPresented: Bool
    
    // Available presets with their display names
    private let availablePresets: [(preset: AVCaptureSession.Preset, name: String)] = [
        (.hd1920x1080, "1080p"),
        (.hd1280x720, "720p"),
        (.medium, "720p"),
        (.vga640x480, "VGA"),
        (.cif352x288, "CIF")
    ]
    
    private var supportedPresets: [(preset: AVCaptureSession.Preset, name: String)] {
        guard let session = cameraManager.captureSession else { return availablePresets }
        return availablePresets.filter { session.canSetSessionPreset($0.preset) }
    }

    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("Resolution")) {
                    ForEach(supportedPresets, id: \.preset.rawValue) { item in
                        Button(action: {
                            cameraManager.setSessionPreset(item.preset)
                            isPresented = false
                        }) {
                            HStack {
                                Text(item.name)
                                Spacer()
                                if cameraManager.currentResolution == resolutionString(for: item.preset) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    if cameraManager.captureSession == nil {
                        Text("No camera connected")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Video Settings")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
    }
    
    private func resolutionString(for preset: AVCaptureSession.Preset) -> String {
        switch preset {
        case .hd4K3840x2160:
            return "2160p"
        case .hd1920x1080, .high:
            return "1080p"
        case .hd1280x720, .medium:
            return "720p"
        case .low:
            return "480p"
        case .vga640x480:
            return "VGA"
        default:
            return "Unknown"
        }
    }
}