//
//  ChatView.swift
//  RemoteDev
//
//  純正メッセージアプリ風の会話リスト + スレッド。Liquid Glass の吹き出し。
//

import SwiftUI

// MARK: - Models

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    var date = Date()
}

struct Conversation: Identifiable {
    let id = UUID()
    var title: String
    var messages: [ChatMessage]

    var lastMessage: ChatMessage? { messages.last }
}

// MARK: - Sample data

enum SampleData {
    static let conversations: [Conversation] = [
        Conversation(
            title: "RemoteDev",
            messages: [
                ChatMessage(role: .assistant, text: "Hello World"),
                ChatMessage(role: .assistant, text: "RemoteDev テストアプリへようこそ。OpenCode Go のチャットがここに入ります。"),
            ]
        ),
        Conversation(
            title: "ようこそ",
            messages: [
                ChatMessage(role: .assistant, text: "Liquid Glass デザインのチャットシェルです。")
            ]
        ),
    ]
}

// MARK: - Conversation list

struct ChatListView: View {
    @State private var conversations: [Conversation] = SampleData.conversations

    var body: some View {
        NavigationStack {
            List {
                ForEach(conversations.indices, id: \.self) { index in
                    NavigationLink {
                        ThreadView(conversation: $conversations[index])
                    } label: {
                        ConversationRow(conversation: conversations[index])
                    }
                }
            }
            .navigationTitle("チャット")
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Text(String(conversation.title.prefix(1)))
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .glassEffect(in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.body.weight(.semibold))
                Text(conversation.lastMessage?.text ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thread

struct ThreadView: View {
    @Binding var conversation: Conversation
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    if let last = conversation.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            ComposerBar(text: $draft) { send() }
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        conversation.messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        // テスト用の仮返信。実 API 接続は次フェーズ。
        conversation.messages.append(ChatMessage(role: .assistant, text: "テスト返信: \(text)"))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }

            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(isUser ? .white : .primary)
                .background {
                    if isUser {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor)
                    }
                }
                .modifier(AssistantGlassModifier(isUser: isUser))

            if !isUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
    }
}

/// アシスタント側の吹き出しにだけ Liquid Glass を当てる
private struct AssistantGlassModifier: ViewModifier {
    let isUser: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isUser {
            content
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .glassEffect(in: .rect(cornerRadius: 18))
        }
    }
}

// MARK: - Composer

struct ComposerBar: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("メッセージ", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.glass)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    ChatListView()
}
