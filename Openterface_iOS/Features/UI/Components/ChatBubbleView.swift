//
//  ChatBubbleView.swift
//  Openterface_iOS
//

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let onQuickReply: (ChatQuickReply) -> Void

    var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            // Content bubble
            VStack(alignment: .leading, spacing: 6) {
                // Image attachment
                if let path = message.attachmentFilePath {
                    AsyncImage(url: URL(fileURLWithPath: path)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 250, maxHeight: 200)
                                .cornerRadius(8)
                        case .failure:
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundColor(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                }

                // Text content
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(isUser ? .white : .primary)
                        .textSelection(.enabled)
                }

                // Quick reply chips
                if let quickReplies = message.quickReplies, !quickReplies.isEmpty, !isUser {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                        ForEach(quickReplies) { reply in
                            Button(action: { onQuickReply(reply) }) {
                                Text(reply.label)
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isUser ? Color.accentColor : Color(.systemGray6))
            )

            // Timestamp
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
