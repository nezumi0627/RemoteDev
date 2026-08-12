//
//  ChatView.swift
//  RemoteDev
//
//  純正メッセージアプリ風のチャット。コピー・リプライ・編集・再送信・画像添付に対応。
//  画像付きターンは mimo (vision)、ふだんは deepseek を使う。
//

import SwiftUI
import UIKit

// MARK: - Models

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var model: String?
    var durationMs: Double?
    var isEdited = false
    var replyingToID: UUID?
    var images: [Data] = []

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
                ChatMessage(role: .assistant, text: "RemoteDev へようこそ。OpenCode Go と会話できます。\n設定タブで API キーを入力してください。"),
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

enum MessageAction {
    case copy, reply, edit, resend, regenerate, saveEdit, cancelEdit
}

struct ThreadView: View {
    @Binding var conversation: Conversation

    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?

    @State private var replyToMessage: ChatMessage?
    @State private var pendingImages: [Data] = []
    @State private var showPhotoPicker = false
    @State private var editingID: UUID?
    @State private var editDraft = ""
    @State private var copiedMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(conversation.messages) { message in
                            MessageBubble(
                                message: message,
                                repliedText: repliedText(for: message),
                                isEditing: editingID == message.id,
                                editText: $editDraft,
                                isCopied: copiedMessageID == message.id,
                                onAction: { handleAction($0, for: message) }
                            )
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

            if let replyToMessage {
                ReplyBar(text: replyToMessage.text) { self.replyToMessage = nil }
            }
            if !pendingImages.isEmpty {
                PendingImagesRow(images: pendingImages) { removeImage($0) }
            }
            ComposerBar(
                text: $draft,
                isEnabled: !isStreaming,
                canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty,
                onAttach: { showPhotoPicker = true },
                onSend: { send() }
            )

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
            ToolbarItem(placement: .topBarTrailing) {
                if isStreaming {
                    Button("停止") { stopStreaming() }
                } else {
                    Menu {
                        ForEach(AppConfig.goChatModels, id: \.self) { model in
                            Button(model) { AppConfig.setChatModel(model) }
                        }
                    } label: {
                        Label(AppConfig.chatModel, systemImage: "cpu")
                    }
                }
            }
        }
        .task(id: copiedMessageID) {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copiedMessageID = nil }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { images in
                pendingImages.append(contentsOf: images)
            }
        }
        .onDisappear { stopStreaming() }
    }

    // MARK: - Actions

    private func handleAction(_ action: MessageAction, for message: ChatMessage) {
        switch action {
        case .copy:
            UIPasteboard.general.string = message.text
            copiedMessageID = message.id
        case .reply:
            replyToMessage = message
        case .edit:
            editingID = message.id
            editDraft = message.text
        case .resend:
            resend(message)
        case .regenerate:
            regenerate(message)
        case .saveEdit:
            saveEdit(message)
        case .cancelEdit:
            editingID = nil
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty, !isStreaming else { return }
        guard !AppConfig.apiKey.isEmpty else {
            errorMessage = "API キーが未設定です。設定タブで入力してください。"
            return
        }
        let images = pendingImages.compactMap { resizedJPEG($0) }
        conversation.messages.append(ChatMessage(role: .user, text: text, replyingToID: replyToMessage?.id, images: images))
        draft = ""
        pendingImages = []
        replyToMessage = nil
        streamAssistant()
    }

    private func resend(_ message: ChatMessage) {
        guard !isStreaming else { return }
        conversation.messages.append(ChatMessage(role: .user, text: message.text, replyingToID: message.replyingToID, images: message.images))
        streamAssistant()
    }

    private func regenerate(_ message: ChatMessage) {
        guard !isStreaming, let index = conversation.messages.firstIndex(where: { $0.id == message.id }) else { return }
        conversation.messages.removeSubrange(index...)
        streamAssistant()
    }

    private func saveEdit(_ message: ChatMessage) {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = conversation.messages.firstIndex(where: { $0.id == message.id }) else {
            editingID = nil
            return
        }
        conversation.messages[index].text = text
        conversation.messages[index].isEdited = true
        editingID = nil
        if index + 1 < conversation.messages.count {
            conversation.messages.removeSubrange((index + 1)...)
        }
        streamAssistant()
    }

    // MARK: - Streaming

    private func streamAssistant() {
        guard !isStreaming else { return }
        guard !AppConfig.apiKey.isEmpty else {
            errorMessage = "API キーが未設定です。設定タブで入力してください。"
            return
        }
        // 画像付きターンは mimo (vision)、ふだんは deepseek
        let lastUser = conversation.messages.last { $0.isUser }
        let useVision = lastUser?.images.isEmpty == false
        let model = useVision ? AppConfig.imageVisionModel : AppConfig.chatModel

        let placeholder = ChatMessage(role: .assistant, text: "")
        conversation.messages.append(placeholder)
        let messageIndex = conversation.messages.count - 1
        let start = Date()

        let client = APIClient(baseURL: AppConfig.baseURL, apiKey: AppConfig.apiKey, model: model)
        let history = conversation.messages.prefix(messageIndex).map { apiMessage(for: $0) }

        isStreaming = true
        errorMessage = nil
        streamTask = Task {
            do {
                let stream = client.streamChat(messages: Array(history))
                for try await delta in stream {
                    conversation.messages[messageIndex].text += delta
                }
                if conversation.messages[messageIndex].text.isEmpty {
                    conversation.messages[messageIndex].text = "(空の応答)"
                }
                conversation.messages[messageIndex].model = model
                conversation.messages[messageIndex].durationMs = Date().timeIntervalSince(start) * 1000
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

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        if let last = conversation.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - Helpers

    private func apiMessage(for message: ChatMessage) -> APIMessage {
        var content = message.text
        if let replyID = message.replyingToID,
           let replied = conversation.messages.first(where: { $0.id == replyID }),
           !replied.text.isEmpty {
            let quoted = replied.text.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
            content = quoted + "\n\n" + content
        }
        return APIMessage(role: message.isUser ? "user" : "assistant", content: content, images: message.images)
    }

    private func repliedText(for message: ChatMessage) -> String? {
        guard let id = message.replyingToID,
              let replied = conversation.messages.first(where: { $0.id == id }) else { return nil }
        return replied.text
    }

    private func removeImage(at index: Int) {
        guard pendingImages.indices.contains(index) else { return }
        pendingImages.remove(at: index)
    }

    /// 送信前に画像を縮小して JPEG 化 (ペイロード肥大防止)
    private func resizedJPEG(_ data: Data, maxDimension: CGFloat = 1280, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let width = image.size.width, height = image.size.height
        let scale = min(1, maxDimension / max(width, height))
        let newSize = CGSize(width: width * scale, height: height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - 吹き出し

struct MessageBubble: View {
    let message: ChatMessage
    let repliedText: String?
    let isEditing: Bool
    @Binding var editText: String
    let isCopied: Bool
    let onAction: (MessageAction) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isUser { Spacer(minLength: 56) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if let repliedText, !repliedText.isEmpty {
                    ReplyQuote(text: repliedText)
                }
                if isEditing {
                    editView
                } else {
                    contentView
                }
                footer
            }
            .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button { onAction(.copy) } label: { Label("コピー", systemImage: "doc.on.doc") }
            Button { onAction(.reply) } label: { Label("返信", systemImage: "arrowshape.turn.up.left") }
            if message.isUser {
                Button { onAction(.edit) } label: { Label("編集", systemImage: "pencil") }
                Button { onAction(.resend) } label: { Label("再送信", systemImage: "arrow.clockwise") }
            } else {
                Button { onAction(.regenerate) } label: { Label("再生成", systemImage: "arrow.counterclockwise") }
            }
        }
    }

    private var contentView: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            if !message.images.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(message.images.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(message.isUser ? .white : .primary)
        .background { bubbleBackground }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
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

    private var editView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("編集", text: $editText, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { onAction(.cancelEdit) }
                Button("保存") { onAction(.saveEdit) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if message.isUser {
                Spacer()
                if message.isEdited {
                    Text("編集済み").font(.caption2).foregroundStyle(.secondary)
                }
                copyButton
            } else {
                if let model = message.model {
                    Text(model).font(.caption2).foregroundStyle(.secondary)
                }
                if let ms = message.durationMs, ms > 0 {
                    Text(String(format: "%.1f秒", ms / 1000)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                copyButton
            }
        }
        .font(.caption2)
    }

    private var copyButton: some View {
        Button { onAction(.copy) } label: {
            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(isCopied ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Telegram 風ポップ背景

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

// MARK: - リプライ / 添付 / 入力

struct ReplyQuote: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(.secondary.opacity(0.6)).frame(width: 3)
            Text(text.split(separator: "\n").first.map(String.init) ?? text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ReplyBar: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("返信").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                Text(text.split(separator: "\n").first.map(String.init) ?? text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct PendingImagesRow: View {
    let images: [Data]
    let onRemove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Button { onRemove(index) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .padding(2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 4)
    }
}

struct ComposerBar: View {
    @Binding var text: String
    var isEnabled: Bool = true
    var canSend: Bool = true
    let onAttach: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAttach) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

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
            .disabled(!isEnabled || !canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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

#Preview {
    ChatListView()
        .environment(AppModel())
}
