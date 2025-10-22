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
        (.hd4K3840x2160, "2160p (4K)"),
        (.hd1920x1080, "1080p"),
        (.hd1280x720, "720p"),
        (.medium, "720p"),
        (.low, "480p"),
        (.vga640x480, "VGA"),
        (.cif352x288, "CIF")
    ]
    
    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("Resolution")) {
                    ForEach(availablePresets, id: \.preset.rawValue) { item in
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