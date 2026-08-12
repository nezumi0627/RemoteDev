//
//  ChatView.swift
//  RemoteDev
//
//  純正メッセージアプリ風の会話リスト + スレッド。OpenCode Zen とストリーミング会話。
//

import SwiftUI

// MARK: - Models

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    var date = Date()

    var isUser: Bool { role == .user }
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
                ChatMessage(role: .assistant, text: "RemoteDev へようこそ。OpenCode Zen と会話できます。設定タブで API キーを入力してください。"),
            ]
        ),
    ]
}

// MARK: - Conversation list

struct ChatListView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        NavigationStack {
            List {
                ForEach(model.conversations.indices, id: \.self) { index in
                    NavigationLink {
                        ThreadView(conversation: $model.conversations[index])
                    } label: {
                        ConversationRow(conversation: model.conversations[index])
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
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isStreaming {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .background(PopWallpaper())
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToLast(proxy)
                }
                .onChange(of: conversation.messages.last?.text) { _, _ in
                    scrollToLast(proxy)
                }
            }

            ComposerBar(text: $draft, isEnabled: !isStreaming) { send() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isStreaming {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("停止") { stopStreaming() }
                }
            }
        }
        .onDisappear { stopStreaming() }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        if let last = conversation.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard !AppConfig.apiKey.isEmpty else {
            errorMessage = "API キーが未設定です。設定タブで入力してください。"
            return
        }

        conversation.messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        errorMessage = nil

        let placeholder = ChatMessage(role: .assistant, text: "")
        conversation.messages.append(placeholder)
        let messageIndex = conversation.messages.count - 1

        let client = APIClient(baseURL: AppConfig.baseURL, apiKey: AppConfig.apiKey, model: AppConfig.chatModel)
        let history = conversation.messages.prefix(messageIndex).map {
            APIMessage(role: $0.isUser ? "user" : "assistant", content: $0.text)
        }

        isStreaming = true
        streamTask = Task {
            do {
                let stream = client.streamChat(messages: Array(history))
                for try await delta in stream {
                    conversation.messages[messageIndex].text += delta
                }
                if conversation.messages[messageIndex].text.isEmpty {
                    conversation.messages[messageIndex].text = "(空の応答)"
                }
            } catch {
                if !Task.isCancelled {
                    conversation.messages[messageIndex].text = "(エラー)"
                    errorMessage = error.localizedDescription
                }
            }
            isStreaming = false
            streamTask = nil
        }
    }
}

// MARK: - Telegram 風ポップ背景と吹き出し

struct PopWallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.48, blue: 0.90),
                Color(red: 0.55, green: 0.28, blue: 0.85),
                Color(red: 0.93, green: 0.36, blue: 0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isUser { Spacer(minLength: 56) }

            Text(message.text.isEmpty ? "…" : message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(message.isUser ? .white : .primary)
                .background {
                    if message.isUser {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 0.27, green: 0.55, blue: 0.95),
                                    Color(red: 0.38, green: 0.76, blue: 0.98),
                                ],
                                startPoint: .top, endPoint: .bottom
                            ))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .systemBackground).opacity(0.92))
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animate ? -4 : 2)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever().delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground).opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
        .onAppear { animate = true }
    }
}

// MARK: - Composer

struct ComposerBar: View {
    @Binding var text: String
    var isEnabled: Bool = true
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
            .disabled(!isEnabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .environment(AppModel())
}
