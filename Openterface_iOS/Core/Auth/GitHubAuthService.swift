//
//  GitHubAuthService.swift
//  Openterface_iOS
//

import Foundation
import AuthenticationServices
import Combine
import UIKit

final class GitHubAuthService: ObservableObject {

    // MARK: - Published State

    @Published var isLoggedIn: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var loginError: String?

    // MARK: - Internal State

    private var authSession: ASWebAuthenticationSession?

    // MARK: - Constants

    static let backendBaseURL = "http://beets3d.cn:46009"
    static let oauthLoginPath = "/auth/github/login"
    static let callbackScheme = "openterface"
    static let apiKeyKeychainKey = "github_api_key"

    // MARK: - Public API

    func checkLoginStatus() {
        let hasKey = KeychainService.shared.get(key: Self.apiKeyKeychainKey) != nil
        print("🔐 GitHubAuthService: checkLoginStatus — Keychain key exists: \(hasKey)")
        DispatchQueue.main.async {
            self.isLoggedIn = hasKey
        }
    }

    @MainActor
    func login() async -> Bool {
        guard !isAuthenticating else {
            print("🔐 GitHubAuthService: login() called while already authenticating, ignoring")
            return false
        }

        loginError = nil
        isAuthenticating = true

        defer {
            isAuthenticating = false
            print("🔐 GitHubAuthService: isAuthenticating set to false (defer)")
        }

        let fullURL = Self.backendBaseURL + Self.oauthLoginPath
        print("🔐 GitHubAuthService: login() called, opening auth URL: \(fullURL)")
        print("🔐 GitHubAuthService: callback scheme = \(Self.callbackScheme)")

        guard let authURL = URL(string: fullURL) else {
            loginError = "Invalid OAuth URL"
            print("🔐 GitHubAuthService: ERROR — authURL could not be created: \(fullURL)")
            return false
        }

        return await withCheckedContinuation { continuation in
            print("🔐 GitHubAuthService: Creating ASWebAuthenticationSession…")
            let presentationProvider = PresentationContextProvider()
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self else {
                        print("🔐 GitHubAuthService: self is nil in callback")
                        continuation.resume(returning: false)
                        return
                    }
                    defer { self.finishAuth() }
                    print("🔐 GitHubAuthService: ASWebAuthenticationSession callback received")

                    if let error = error {
                        let nsError = error as NSError
                        print("🔐 GitHubAuthService: ERROR from session — code: \(nsError.code), domain: \(nsError.domain), message: \(nsError.localizedDescription)")
                        if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            print("🔐 GitHubAuthService: User cancelled login")
                            self.loginError = nil
                        } else {
                            self.loginError = error.localizedDescription
                        }
                        continuation.resume(returning: false)
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        print("🔐 GitHubAuthService: ERROR — callbackURL is nil (no error either)")
                        self.loginError = "No callback received from server"
                        continuation.resume(returning: false)
                        return
                    }

                    print("🔐 GitHubAuthService: Received callback URL: \(callbackURL.absoluteString)")
                    print("🔐 GitHubAuthService: scheme=\(callbackURL.scheme ?? "(nil)"), host=\(callbackURL.host ?? "(nil)"), query=\(callbackURL.query ?? "(nil)")")

                    if let apiKey = Self.parseAPIKey(from: callbackURL) {
                        print("🔐 GitHubAuthService: Extracted API key from callback: \(String(apiKey.prefix(8)))…\(String(apiKey.suffix(4)))")
                        let saved = KeychainService.shared.set(string: apiKey, key: Self.apiKeyKeychainKey)
                        print("🔐 GitHubAuthService: Keychain save result: \(saved)")
                        if saved {
                            self.isLoggedIn = true
                            self.loginError = nil
                            print("🔐 GitHubAuthService: Login successful, isLoggedIn = true")
                            continuation.resume(returning: true)
                        } else {
                            self.loginError = "Failed to securely store API key"
                            print("🔐 GitHubAuthService: ERROR — Keychain set failed")
                            continuation.resume(returning: false)
                        }
                    } else {
                        print("🔐 GitHubAuthService: ERROR — Could not extract API key from callback URL: \(callbackURL.absoluteString)")
                        self.loginError = "Could not extract API key from callback"
                        continuation.resume(returning: false)
                    }
                }
            }

            self.authSession = session
            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = true
            let started = session.start()
            print("🔐 GitHubAuthService: session.start() returned: \(started)")
        }
    }

    private func finishAuth() {
        authSession = nil
    }

    func logout() {
        print("🔐 GitHubAuthService: logout called")
        authSession?.cancel()
        authSession = nil
        _ = KeychainService.shared.delete(key: Self.apiKeyKeychainKey)
        DispatchQueue.main.async {
            self.isLoggedIn = false
            self.loginError = nil
            print("🔐 GitHubAuthService: logout complete, isLoggedIn = false")
        }
    }

    // MARK: - Parsing

    static func parseAPIKey(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            print("🔐 GitHubAuthService: parseAPIKey — URLComponents or queryItems is nil, url=\(url)")
            return nil
        }

        print("🔐 GitHubAuthService: parseAPIKey — query items: \(queryItems.map { "\($0.name)=\($0.value ?? "(nil)")" })")

        for key in ["key", "api_key", "apiKey", "token", "access_token"] {
            if let value = queryItems.first(where: { $0.name == key })?.value, !value.isEmpty {
                print("🔐 GitHubAuthService: parseAPIKey — matched key '\(key)', value length=\(value.count)")
                return value
            }
        }
        print("🔐 GitHubAuthService: parseAPIKey — no matching key found in query items")
        return nil
    }
}

// MARK: - Presentation Context Provider

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
