//
//  ChatModels.swift
//  Openterface_iOS
//

import Foundation

// MARK: - Chat Role

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: ChatRole
    var content: String
    var attachmentFilePath: String?
    var quickReplies: [ChatQuickReply]?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachmentFilePath: String? = nil,
        quickReplies: [ChatQuickReply]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachmentFilePath = attachmentFilePath
        self.quickReplies = quickReplies
        self.createdAt = createdAt
    }
}

// MARK: - Quick Reply

struct ChatQuickReply: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var sendText: String

    init(id: UUID = UUID(), label: String, sendText: String) {
        self.id = id
        self.label = label
        self.sendText = sendText
    }
}

// MARK: - API Configuration

struct ChatAPIConfiguration {
    let baseURL: URL
    let model: String
    let apiKey: String
}

// MARK: - API Request / Response

struct ChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        struct ContentPart: Encodable {
            struct ImageURLPayload: Encodable {
                let url: String
            }

            let type: String
            let text: String?
            let image_url: ImageURLPayload?

            static func text(_ text: String) -> ContentPart {
                ContentPart(type: "text", text: text, image_url: nil)
            }

            static func image(_ url: String) -> ContentPart {
                ContentPart(type: "image_url", text: nil, image_url: .init(url: url))
            }
        }

        let role: ChatRole
        let content: Content

        enum Content: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let value): try container.encode(value)
                case .parts(let value): try container.encode(value)
                }
            }
        }

        static func text(role: ChatRole, text: String) -> Message {
            Message(role: role, content: .text(text))
        }

        static func multimodal(role: ChatRole, text: String, imageDataURL: String) -> Message {
            Message(role: role, content: .parts([.text(text), .image(imageDataURL)]))
        }
    }

    let model: String
    let messages: [Message]
    let stream: Bool = false

    init(model: String, messages: [Message]) {
        self.model = model
        self.messages = messages
    }
}

struct ChatCompletionsResponse: Decodable {
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    let choices: [Choice]
    let usage: Usage?
}

// MARK: - Internal Types

struct ChatCompletionResult {
    let content: String
    let inputTokenCount: Int?
    let outputTokenCount: Int?
}

struct AgentToolExecutionResult {
    let summary: String
    let attachmentFilePath: String?
    let keyboardOnlyMacroData: String?

    init(summary: String, attachmentFilePath: String?, keyboardOnlyMacroData: String? = nil) {
        self.summary = summary
        self.attachmentFilePath = attachmentFilePath
        self.keyboardOnlyMacroData = keyboardOnlyMacroData
    }
}

struct AgentToolCall {
    let tool: String
    let args: [String: Any]
}
