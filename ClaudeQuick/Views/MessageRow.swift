import SwiftUI

struct MessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Avatar
                VStack {
                    if message.role == .user {
                        Image(systemName: "person.fill")
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Circle())
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "sparkles")
                            .frame(width: 32, height: 32)
                            .background(Color.purple.opacity(0.2))
                            .clipShape(Circle())
                            .foregroundColor(.purple)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Role Label
                    HStack {
                        Text(message.role == .user ? "You" : "Claude")
                            .font(.caption)
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Content
                    Text(message.content)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .font(.body)
                        .padding(12)
                        .background(message.role == .user ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
                        .cornerRadius(8)

                    // Context Info
                    if let context = message.contextSnapshot, context.tokensUsed > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.plus")
                                .font(.caption2)

                            Text("\(context.tokensUsed) tokens")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                    .frame(width: 12)
            }

            // Copy Button
            HStack {
                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
            }
            .opacity(0.7)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageRow(message: Message(
            conversationId: UUID(),
            role: .user,
            content: "What is Swift?"
        ))

        MessageRow(message: Message(
            conversationId: UUID(),
            role: .assistant,
            content: "Swift is a powerful and intuitive programming language for iOS, macOS, watchOS, and tvOS. It's designed to be fast, safe, and expressive."
        ))
    }
    .padding(16)
}
