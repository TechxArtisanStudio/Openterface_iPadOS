//
//  ChatView.swift
//  Openterface_iOS
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var authService: GitHubAuthService
    @ObservedObject var appCoordinator: AppCoordinator
    @Binding var showLoginSheet: Bool
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Not signed in warning
                if !authService.isLoggedIn {
                    notSignedInBanner
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if chatManager.messages.isEmpty {
                                emptyState
                            } else {
                                ForEach(chatManager.messages) { message in
                                    ChatBubbleView(
                                        message: message,
                                        onQuickReply: { reply in
                                            chatManager.sendQuickReply(reply)
                                        }
                                    )
                                    .id(message.id)
                                }
                            }

                            // Loading indicator
                            if chatManager.isSending {
                                HStack {
                                    ProgressView()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    Spacer()
                                    Button("Stop") {
                                        chatManager.cancelSending()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                                .padding(.horizontal, 12)
                                .id("loading")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: chatManager.messages.count) { _ in
                        withAnimation {
                            if let lastID = chatManager.messages.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: chatManager.isSending) { sending in
                        if sending {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input area
                inputBar
            }
            .navigationTitle("AI Assistant (Beta)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        if let onDone {
                            onDone()
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    accountButton
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(appCoordinator: appCoordinator)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Account Button

    private var accountButton: some View {
        Button {
            if authService.isLoggedIn {
                showSettings = true
            } else {
                dismiss()
                showLoginSheet = true
            }
        } label: {
            if authService.isLoggedIn {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.primaryAccent)
                }
            } else {
                Image(systemName: "person.circle")
            }
        }
    }

    // MARK: - Not Signed In Banner

    private var notSignedInBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
            Text("Sign in required.")
                .font(.caption)
                .foregroundColor(.orange)
            Spacer()
            Button("Sign In") {
                dismiss()
                showLoginSheet = true
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message.and.waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Ask AI to help control your target device")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Try: \"Take a screenshot\" or \"Type hello world\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onTapGesture {
                    isInputFocused = true
                }
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrowshape.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
            }
            .disabled(!authService.isLoggedIn || (inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatManager.isSending))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isInputFocused = false
        inputText = ""
        chatManager.sendMessage(trimmed)
    }
}
