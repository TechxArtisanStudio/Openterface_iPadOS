//
//  LoginView.swift
//  Openterface_iOS
//

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var authService: GitHubAuthService

    @State private var showLoginError = false

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                // GitHub icon
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.primary)

                Text("Sign in to AI Assistant")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Sign in with your GitHub account to access the AI assistant features.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Login button
                Button(action: performLogin) {
                    HStack(spacing: 12) {
                        if authService.isAuthenticating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "person.badge.key.fill")
                        }
                        Text(authService.isAuthenticating ? "Signing in..." : "Sign in with GitHub")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(authService.isAuthenticating)

                if let error = authService.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationTitle("AI Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: authService.isLoggedIn) { loggedIn in
                if loggedIn {
                    dismiss()
                }
            }
        }
    }

    private func performLogin() {
        print("🔐 LoginView: performLogin called")
        Task {
            let result = await authService.login()
            print("🔐 LoginView: login result = \(result)")
        }
    }
}

#Preview {
    LoginView(authService: GitHubAuthService())
}
