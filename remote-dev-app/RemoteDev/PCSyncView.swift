//
//  PCSyncView.swift
//  RemoteDev
//
//  PC コンパニオン同期タブ。会話の引き継ぎ・進捗・スキル・MCP を WiFi 経由で表示。
//

import SwiftUI

// MARK: - Decodable models (PC server のレスポンス)

struct PCConversation: Codable, Identifiable {
    let id: String
    let project: String
    let name: String
    let mtime: String
    let messages: Int
    let preview: String
}

struct PCTurn: Codable {
    let role: String
    let text: String
}

struct TranscriptResponse: Codable {
    let turns: [PCTurn]
}

struct PCProgressEntry: Codable, Hashable {
    let role: String
    let text: String
    let timestamp: String
}

struct PCProgress: Codable {
    let file: String?
    let entries: [PCProgressEntry]
}

struct PCSkill: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
}

struct SkillResponse: Codable {
    let name: String
    let content: String
}

struct PCServer: Codable, Identifiable {
    let name: String
    let command: String?
    var id: String { name }
}

// MARK: - View

struct PCSyncView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppConfig.pcHostKey) private var pcHost = ""
    @AppStorage(AppConfig.pcPortKey) private var pcPort = "8000"

    @State private var conversations: [PCConversation] = []
    @State private var progress: PCProgress?
    @State private var skills: [PCSkill] = []
    @State private var servers: [PCServer] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var statusText = ""

    private var baseURL: String { "http://\(pcHost):\(pcPort)" }
    private var client: PCClient { PCClient(baseURL: baseURL) }

    var body: some View {
        NavigationStack {
            Form {
                Section("PC 接続") {
                    HStack {
                        TextField("PC の IP アドレス", text: $pcHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                        TextField("ポート", text: $pcPort)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }
                    Button {
                        Task { await loadAll() }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("接続して読み込む")
                        }
                    }
                    .disabled(pcHost.isEmpty || isLoading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("PC の進行状況（Claude Code）") {
                    if let progress, let file = progress.file {
                        Text(file)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ForEach(progress.entries, id: \.self) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp)
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .leading)
                                Text(entry.text.isEmpty ? "(ツール操作)" : entry.text)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Text("進捗なし")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Claude の会話（引き継ぎ）") {
                    if conversations.isEmpty {
                        Text("会話なし（接続してください）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(conversations.prefix(15)) { conversation in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.project)
                                    .font(.subheadline.weight(.medium))
                                Text(conversation.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("引き継ぐ") {
                                Task { await handoff(conversation) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                Section("スキル") {
                    ForEach(skills) { skill in
                        NavigationLink {
                            SkillDetailView(skillID: skill.id, client: client)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.subheadline.weight(.medium))
                                Text(skill.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Section("MCP サーバ") {
                    ForEach(servers) { server in
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.subheadline.weight(.medium))
                                if let command = server.command {
                                    Text(command)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !statusText.isEmpty {
                    Section {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("PC同期")
            .task { await loadAll() }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                guard appModel.selectedTab == .pc, !pcHost.isEmpty, !isLoading else { return }
                Task { await loadProgressOnly() }
            }
        }
    }

    // MARK: - Actions

    private func loadAll() async {
        guard !pcHost.isEmpty else {
            errorMessage = "PC の IP アドレスを入力してください"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let c: [PCConversation] = try fetchConversations()
            async let s: [PCSkill] = try fetchSkills()
            async let m: [PCServer] = try fetchServers()
            async let p: PCProgress = try fetchProgress()
            conversations = try await c
            skills = try await s
            servers = try await m
            progress = try await p
            statusText = "接続 OK（\(conversations.count) 会話 / \(skills.count) スキル / \(servers.count) MCP）"
        } catch {
            errorMessage = "PC に接続できません: \(error.localizedDescription)"
            statusText = ""
        }
        isLoading = false
    }

    private func loadProgressOnly() async {
        do {
            progress = try await fetchProgress()
        } catch {
            // 定期更新の失敗は無視（初回エラーは loadAll で表示済み）
        }
    }

    private func fetchConversations() async throws -> [PCConversation] {
        let response: ConversationListResponse = try await client.get("/api/conversations", as: ConversationListResponse.self)
        return response.conversations
    }

    private func fetchSkills() async throws -> [PCSkill] {
        let response: SkillListResponse = try await client.get("/api/skills", as: SkillListResponse.self)
        return response.skills
    }

    private func fetchServers() async throws -> [PCServer] {
        let response: ServerListResponse = try await client.get("/api/mcp", as: ServerListResponse.self)
        return response.servers
    }

    private func fetchProgress() async throws -> PCProgress {
        try await client.get("/api/progress", as: PCProgress.self)
    }

    private func handoff(_ conversation: PCConversation) async {
        guard let encodedID = conversation.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        do {
            let response: TranscriptResponse = try await client.get(
                "/api/transcript?id=\(encodedID)", as: TranscriptResponse.self
            )
            let messages = response.turns.map {
                ChatMessage(role: $0.role == "user" ? .user : .assistant, text: $0.text)
            }
            appModel.addHandoffConversation(Conversation(title: "引継: \(conversation.project)", messages: messages))
            statusText = "「\(conversation.project)」を引き継ぎました"
        } catch {
            statusText = "引き継ぎ失敗: \(error.localizedDescription)"
        }
    }
}

struct ConversationListResponse: Codable { let conversations: [PCConversation] }
struct SkillListResponse: Codable { let skills: [PCSkill] }
struct ServerListResponse: Codable { let servers: [PCServer] }

// MARK: - Skill detail

struct SkillDetailView: View {
    let skillID: String
    let client: PCClient
    @State private var content: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let content {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle(skillID)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func load() async {
        guard let encoded = skillID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        do {
            let response: SkillResponse = try await client.get("/api/skill?name=\(encoded)", as: SkillResponse.self)
            content = response.content
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    PCSyncView()
        .environment(AppModel())
}
