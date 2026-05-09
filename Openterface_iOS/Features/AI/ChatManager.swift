//
//  ChatManager.swift
//  Openterface_iOS
//

import Foundation
import Combine

final class ChatManager: ObservableObject {

    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    @Published var isSending: Bool = false
    @Published var lastError: String?

    // MARK: - Internal State

    var agentMouseX: Double = 0.5
    var agentMouseY: Double = 0.5
    var currentTask: Task<Void, Never>?

    // MARK: - Services

    private(set) lazy var conversationBuilder = ChatConversationBuilderService(
        macroManager: macroManager,
        targetOS: { [weak self] in self?.targetOS() ?? .windows }
    )
    private(set) lazy var screenCapture = ChatScreenCaptureService(cameraManager: cameraManager)
    private(set) lazy var toolExecution = ChatToolExecutionService(
        keyboardManager: keyboardManager,
        mouseManager: mouseManager,
        macroManager: macroManager,
        screenCapture: screenCapture,
        conversationBuilder: conversationBuilder
    )

    // MARK: - Dependencies

    private let keyboardManager: KeyboardInputManager
    private let mouseManager: MouseInputManager
    private let macroManager: MacroInputManager
    private let cameraManager: CameraSessionManager
    private let targetOS: () -> MacroTargetSystem

    private let defaultsKey = "ChatHistory_v1"
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - UserDefaults Keys

    static let isAIEnabledKey = "AIIntegrationEnabled"
    static let baseURLKey = "ChatAPIBaseURL"
    static let modelKey = "ChatAPIModel"
    static let maxIterationsKey = "ChatAgentMaxIterations"
    static let systemPromptKey = "ChatSystemPrompt"

    // Hardcoded AI service endpoint
    static let defaultBaseURL = "http://beets3d.cn:46009/api/v1"

    // MARK: - Initialization

    init(
        keyboardManager: KeyboardInputManager,
        mouseManager: MouseInputManager,
        macroManager: MacroInputManager,
        cameraManager: CameraSessionManager,
        targetOS: @escaping () -> MacroTargetSystem
    ) {
        self.keyboardManager = keyboardManager
        self.mouseManager = mouseManager
        self.macroManager = macroManager
        self.cameraManager = cameraManager
        self.targetOS = targetOS
        loadHistory()
    }

    // MARK: - Public API

    func sendMessage(_ text: String, attachmentFileURL: URL? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachmentFileURL != nil else { return }
        guard !isSending else { return }

        lastError = nil
        let storedContent = trimmed.isEmpty ? "Attached screenshot" : trimmed
        let messageID = UUID()
        messages.append(ChatMessage(
            id: messageID,
            role: .user,
            content: storedContent,
            attachmentFilePath: attachmentFileURL?.path
        ))
        persistHistory()
        isSending = true

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend()
        }
    }

    func cancelSending() {
        currentTask?.cancel()
        currentTask = nil
        isSending = false
    }

    func sendQuickReply(_ reply: ChatQuickReply) {
        sendMessage(reply.sendText)
    }

    func clearHistory() {
        cancelSending()
        messages.removeAll()
        lastError = nil
        persistHistory()
    }

    // MARK: - API Configuration

    func currentChatAPIConfiguration() -> ChatAPIConfiguration? {
        let apiKey = KeychainService.shared.get(key: GitHubAuthService.apiKeyKeychainKey)
        guard let apiKey, !apiKey.isEmpty else { return nil }

        // Use hardcoded default or override from UserDefaults
        let baseURLString = UserDefaults.standard.string(forKey: Self.baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? Self.defaultBaseURL
        guard let baseURL = URL(string: baseURLString) else { return nil }

        let model = UserDefaults.standard.string(forKey: Self.modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !model.isEmpty else { return nil }

        return ChatAPIConfiguration(baseURL: baseURL, model: model, apiKey: apiKey)
    }

    // MARK: - Agentic Loop

    func performSend() async {
        guard let config = currentChatAPIConfiguration() else {
            lastError = "Not signed in. Please sign in with GitHub to access the AI assistant."
            isSending = false
            return
        }

        let systemPrompt = UserDefaults.standard.string(forKey: Self.systemPromptKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let maxIterations = UserDefaults.standard.integer(forKey: Self.maxIterationsKey)
        let effectiveMaxIterations = maxIterations > 0 ? maxIterations : 20

        var workingMessages = messages

        for iteration in 1...effectiveMaxIterations {
            guard !Task.isCancelled else { break }

            let conversation = conversationBuilder.buildConversation(
                systemPrompt: systemPrompt,
                sourceMessages: workingMessages,
                includeAgentTools: true
            )

            let payload = ChatCompletionsRequest(model: config.model, messages: conversation)

            do {
                let requestBody = try JSONEncoder().encode(payload)
                var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = requestBody

                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { break }

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "Invalid server response"
                    isSending = false
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let snippet = String(body.prefix(300))
                    lastError = "Chat API error \(httpResponse.statusCode): \(snippet)"
                    isSending = false
                    return
                }

                let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
                guard let assistantText = decoded.choices.first?.message.content, !assistantText.isEmpty else {
                    lastError = "Empty assistant response"
                    isSending = false
                    return
                }

                // Check for tool calls
                if let toolCalls = toolExecution.parseToolCalls(from: assistantText), !toolCalls.isEmpty {
                    let toolResult = await toolExecution.executeToolCalls(toolCalls)
                    workingMessages.append(ChatMessage(role: .assistant, content: assistantText))
                    let toolResultMessage = ChatMessage(
                        role: .user,
                        content: "TOOL_RESULT:\n\(toolResult.summary)",
                        attachmentFilePath: toolResult.attachmentFilePath
                    )
                    workingMessages.append(toolResultMessage)

                    // Update published messages to show progress
                    messages.append(ChatMessage(role: .assistant, content: "Processing..."))
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "Tool result:\n\(toolResult.summary)",
                        attachmentFilePath: toolResult.attachmentFilePath
                    ))
                    persistHistory()
                    continue
                }

                // No tool calls — final response
                let quickReplies = nextActionQuickReplies()
                let finalMsgID = UUID()
                messages.append(ChatMessage(
                    id: finalMsgID,
                    role: .assistant,
                    content: assistantText,
                    quickReplies: quickReplies
                ))
                persistHistory()
                isSending = false
                currentTask = nil
                return

            } catch {
                if Task.isCancelled { break }
                lastError = userFacingErrorMessage(from: error)
                isSending = false
                currentTask = nil
                return
            }
        }

        // Reached iteration limit
        let timeoutMessage = "Reached the configured iteration limit (\(effectiveMaxIterations)). Please provide more guidance or try again."
        messages.append(ChatMessage(role: .assistant, content: timeoutMessage))
        persistHistory()
        isSending = false
        currentTask = nil
    }

    // MARK: - API Call

    func sendChatCompletion(
        baseURL: URL,
        model: String,
        apiKey: String,
        conversation: [ChatCompletionsRequest.Message]
    ) async throws -> ChatCompletionResult {
        let payload = ChatCompletionsRequest(model: model, messages: conversation)
        let requestBody = try JSONEncoder().encode(payload)

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChatError.apiError("API request failed")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw ChatError.emptyResponse
        }

        return ChatCompletionResult(
            content: content,
            inputTokenCount: decoded.usage?.promptTokens,
            outputTokenCount: decoded.usage?.completionTokens
        )
    }

    // MARK: - Helpers

    private func nextActionQuickReplies() -> [ChatQuickReply] {
        [
            ChatQuickReply(label: "Take a screenshot", sendText: "Take a screenshot to show current state"),
            ChatQuickReply(label: "Repeat last task", sendText: "Please repeat the previous task"),
            ChatQuickReply(label: "Something else...", sendText: "")
        ]
    }

    private func userFacingErrorMessage(from error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "No internet connection"
            case .timedOut: return "Request timed out"
            case .cancelled: return "Request cancelled"
            case .badServerResponse: return "Server returned an invalid response"
            default: return "Network error: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Persistence

    private func persistHistory() {
        if let data = try? encoder.encode(messages) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? decoder.decode([ChatMessage].self, from: data)
        else { return }
        messages = saved
    }
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case apiError(String)
    case emptyResponse
    case invalidConfiguration
    case jsonDecodeError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return msg
        case .emptyResponse: return "Empty response from AI"
        case .invalidConfiguration: return "Invalid API configuration"
        case .jsonDecodeError(let msg): return msg
        }
    }
}
