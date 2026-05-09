//
//  SettingsView.swift
//  Openterface_iOS
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    // MARK: - AI Settings State
    @AppStorage("AIIntegrationEnabled") private var isAIEnabled = false
    @State private var aiModel = UserDefaults.standard.string(forKey: ChatManager.modelKey) ?? ""
    @State private var maxIterations = {
        let v = UserDefaults.standard.integer(forKey: ChatManager.maxIterationsKey)
        return v > 0 ? v : 20
    }()

    // MARK: - Recording Settings State
    @State private var saveToPhotoLibrary: Bool = false

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
                } header: {
                    Text("Recording & Screenshots")
                } footer: {
                    Text("When enabled, recordings and screenshots are also saved to the Photos library.")
                }

                // MARK: AI Integration
                Section {
                    Toggle(isOn: $isAIEnabled) {
                        Label("Enable AI Integration", systemImage: "sparkles")
                    }

                    if isAIEnabled {
                        HStack {
                            Label("Model", systemImage: "cpu")
                            Spacer()
                            TextField("e.g. gpt-4o", text: $aiModel)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                        }

                        Stepper(value: $maxIterations, in: 1...30) {
                            Label("Max Iterations: \(maxIterations)", systemImage: "repeat")
                        }
                    }
                } header: {
                    Text("AI Integration")
                } footer: {
                    if isAIEnabled {
                        Text("The AI agent will attempt up to \(maxIterations) steps to complete your request.")
                    } else {
                        Text("Enable AI Integration to show the AI button in the toolbar.")
                    }
                }

                // MARK: Account
                if isAIEnabled {
                    Section("Account") {
                        if appCoordinator.githubAuthService.isLoggedIn {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                Text("Signed in with GitHub")
                                    .foregroundColor(.primary)
                                Spacer()
                                Button("Sign Out", role: .destructive) {
                                    appCoordinator.githubAuthService.logout()
                                }
                            }
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                    .foregroundColor(.secondary)
                                    .font(.title2)
                                Text("Not signed in")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Sign In") {
                                    dismiss()
                                    appCoordinator.showLoginSheet = true
                                }
                            }
                        }
                    }
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
        }
    }

    // MARK: - Save

    private func saveSettings() {
        // AI settings
        UserDefaults.standard.set(aiModel, forKey: ChatManager.modelKey)
        UserDefaults.standard.set(maxIterations, forKey: ChatManager.maxIterationsKey)

        // Recording settings
        var config = appCoordinator.cameraManager.recordingConfiguration
        config.saveToPhotoLibrary = saveToPhotoLibrary
        appCoordinator.cameraManager.updateRecordingConfiguration(config)
    }
}
