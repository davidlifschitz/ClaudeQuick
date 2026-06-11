import SwiftUI

// MARK: - Markdown Parsing

private enum MarkdownSegment {
    case codeBlock(String)
    case inlineText(String)
}

private func splitCodeBlocks(_ text: String) -> [MarkdownSegment] {
    var segments: [MarkdownSegment] = []
    var remaining = text

    while let startRange = remaining.range(of: "```") {
        // Everything before the opening fence is inline text
        let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
        if !before.isEmpty {
            segments.append(.inlineText(before))
        }

        // Find closing fence
        let afterFence = remaining[startRange.upperBound...]
        // Strip optional language identifier on the first line
        var codeContent: String
        if let endRange = afterFence.range(of: "```") {
            codeContent = String(afterFence[afterFence.startIndex..<endRange.lowerBound])
            // Strip optional language tag on first line
            if let newline = codeContent.firstIndex(of: "\n") {
                let firstLine = String(codeContent[codeContent.startIndex..<newline])
                let rest = String(codeContent[codeContent.index(after: newline)...])
                // If the first line has no spaces it's a language tag
                if !firstLine.contains(" ") {
                    codeContent = rest
                }
            }
            segments.append(.codeBlock(codeContent))
            remaining = String(afterFence[endRange.upperBound...])
        } else {
            // No closing fence — treat rest as inline text
            segments.append(.inlineText(String(afterFence)))
            remaining = ""
        }
    }

    if !remaining.isEmpty {
        segments.append(.inlineText(remaining))
    }

    return segments
}

private func attributedStringFromMarkdown(_ text: String) -> AttributedString {
    // Use Foundation's markdown parser when available
    if let attr = try? AttributedString(
        markdown: text,
        options: AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
    ) {
        return attr
    }
    return AttributedString(text)
}

// Process a block of inline text: headings, bullets, numbered lists, then inline markdown
@ViewBuilder
private func renderInlineText(_ text: String, isUserMessage: Bool) -> some View {
    let lines = text.components(separatedBy: "\n")
    VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            lineView(line, isUserMessage: isUserMessage)
        }
    }
}

@ViewBuilder
private func lineView(_ line: String, isUserMessage: Bool) -> some View {
    let trimmed = line.trimmingCharacters(in: .whitespaces)

    if trimmed.hasPrefix("### ") {
        Text(attributedStringFromMarkdown(String(trimmed.dropFirst(4))))
            .font(.subheadline).bold()
    } else if trimmed.hasPrefix("## ") {
        Text(attributedStringFromMarkdown(String(trimmed.dropFirst(3))))
            .font(.headline)
    } else if trimmed.hasPrefix("# ") {
        Text(attributedStringFromMarkdown(String(trimmed.dropFirst(2))))
            .font(.title3).bold()
    } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(attributedStringFromMarkdown(String(trimmed.dropFirst(2))))
        }
    } else if let bullet = numberedListPrefix(trimmed) {
        HStack(alignment: .top, spacing: 6) {
            Text(bullet.prefix)
                .monospacedDigit()
            Text(attributedStringFromMarkdown(bullet.rest))
        }
    } else if trimmed.isEmpty {
        Spacer().frame(height: 4)
    } else {
        Text(attributedStringFromMarkdown(line))
    }
}

private struct NumberedBullet {
    let prefix: String
    let rest: String
}

private func numberedListPrefix(_ text: String) -> NumberedBullet? {
    // Matches "1. " "12. " etc.
    var idx = text.startIndex
    while idx < text.endIndex, text[idx].isNumber {
        idx = text.index(after: idx)
    }
    guard idx > text.startIndex,
          idx < text.endIndex,
          text[idx] == ".",
          text.index(after: idx) < text.endIndex,
          text[text.index(after: idx)] == " " else {
        return nil
    }
    let prefixEnd = text.index(idx, offsetBy: 2)
    return NumberedBullet(
        prefix: String(text[text.startIndex..<prefixEnd]),
        rest: String(text[prefixEnd...])
    )
}

@ViewBuilder
private func parseMarkdown(_ text: String, isUserMessage: Bool) -> some View {
    let segments = splitCodeBlocks(text)
    VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            switch segment {
            case .codeBlock(let code):
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code.trimmingCharacters(in: .newlines))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color(.controlTextColor))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.textBackgroundColor).opacity(0.8))
                .cornerRadius(6)

            case .inlineText(let inline):
                renderInlineText(inline, isUserMessage: isUserMessage)
                    .foregroundColor(isUserMessage ? .white : Color(.labelColor))
            }
        }
    }
}

// MARK: - MessageRow

struct MessageRow: View {
    let message: Message
    @State private var isHovered = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            // Sender name
            Text(isUser ? "You" : "Claude")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(isUser ? .trailing : .leading, 4)

            // Bubble row — cap at 80% of available width
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 0) {
                    if isUser { Spacer(minLength: 0) }

                    ZStack(alignment: .bottomTrailing) {
                        // Bubble content
                        parseMarkdown(message.content, isUserMessage: isUser)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(isUser ? Color.accentColor : Color(.controlBackgroundColor))
                            .cornerRadius(12)

                        // Hover copy button
                        if isHovered {
                            Button(action: copyContent) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                    .padding(5)
                                    .background(Color(.windowBackgroundColor).opacity(0.85))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Copy to clipboard")
                            .padding(6)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: geo.size.width * 0.80, alignment: isUser ? .trailing : .leading)

                    if !isUser { Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            // Token count (assistant only)
            if !isUser, let context = message.contextSnapshot, context.tokensUsed > 0 {
                HStack(spacing: 3) {
                    Text("↑")
                    Text("\(context.tokensUsed) tokens")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(.controlBackgroundColor).opacity(0.7))
                .cornerRadius(8)
                .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
}


#Preview {
    ScrollView {
        VStack(spacing: 16) {
            MessageRow(message: Message(
                conversationId: UUID(),
                role: .user,
                content: "What is **Swift**?"
            ))

            MessageRow(message: Message(
                conversationId: UUID(),
                role: .assistant,
                content: """
                # Swift Overview

                Swift is a **powerful** and *intuitive* programming language.

                ## Key Features

                - Type safety
                - Memory safety
                - Expressive syntax

                ## Example

                ```swift
                let greeting = "Hello, World!"
                print(greeting)
                ```

                Use `let` for constants and `var` for variables.
                """
            ))
        }
        .padding(16)
    }
    .frame(width: 500, height: 600)
}
