import SwiftUI

struct ContextBadge: View {
    @EnvironmentObject var chatViewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.badge.plus")
                    .foregroundColor(.accentColor)

                Text("Attached Context (\(chatViewModel.attachedContext.count))")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Button(action: {
                    chatViewModel.clearContext()
                }) {
                    Text("Clear All")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chatViewModel.attachedContext, id: \.self) { context in
                        ContextItem(
                            context: context,
                            onRemove: {
                                chatViewModel.removeContext(context)
                            }
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Context Item

struct ContextItem: View {
    let context: String
    let onRemove: () -> Void

    var displayName: String {
        URL(fileURLWithPath: context).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)

            Text(displayName)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(4)
    }
}

#Preview {
    ContextBadge()
        .environmentObject(ChatViewModel())
}
