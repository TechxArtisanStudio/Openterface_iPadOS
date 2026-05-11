//
//  SettingsView.swift
//  Openterface_iOS
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    // MARK: - Recording Settings State
    @State private var saveToPhotoLibrary: Bool = false
    @State private var showOpenFolderHelpAlert: Bool = false

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
        _saveToPhotoLibrary = State(initialValue: appCoordinator.cameraManager.recordingConfiguration.saveToPhotoLibrary)
    }

    var body: some View {
        NavigationView {
            Form {
                // MARK: General
                Section("General") {
                    HStack {
                        Label("Keep Screen Awake", systemImage: "sun.max.fill")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .foregroundColor(.primary)
                }

                // MARK: Recording
                Section {
                    Toggle(isOn: $saveToPhotoLibrary) {
                        Label("Save to Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        openRecordingsFolder()
                    } label: {
                        Label("Open Recordings Folder", systemImage: "folder")
                    }
                } header: {
                    Text("Recording & Screenshots")
                } footer: {
                    Text("When enabled, recordings and screenshots are also saved to the Photos library.")
                }

                // MARK: About
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: Save
                Section {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Unable to Open Folder", isPresented: $showOpenFolderHelpAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please open Files and go to On My iPhone/iPad > Openterface KVM > Recordings.")
            }
        }
    }

    // MARK: - Save

    private func saveSettings() {
        // Recording settings
        var config = appCoordinator.cameraManager.recordingConfiguration
        config.saveToPhotoLibrary = saveToPhotoLibrary
        appCoordinator.cameraManager.updateRecordingConfiguration(config)
    }

    private func openRecordingsFolder() {
        let recordingsURL = appCoordinator.cameraManager.getRecordingsDirectory()

        UIApplication.shared.open(recordingsURL, options: [:]) { success in
            if !success {
                showOpenFolderHelpAlert = true
            }
        }
    }
}
