//
//  SettingsView.swift
//  RemoteDev
//
//  API / モデル / PC 接続の設定と API キー動作テスト。オーロラ壁紙 + ガラスカード。
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppConfig.apiKeyKey) private var apiKey = ""
    @AppStorage(AppConfig.baseURLKey) private var baseURL = AppConfig.defaultBaseURL
    @AppStorage(AppConfig.chatModelKey) private var chatModel = AppConfig.defaultModel
    @AppStorage(AppConfig.visionModelKey) private var visionModel = AppConfig.defaultVisionModel
    @AppStorage(AppConfig.imageModelKey) private var imageModel = AppConfig.defaultImageModel
    @AppStorage(AppConfig.pcHostKey) private var pcHost = ""
    @AppStorage(AppConfig.pcPortKey) private var pcPort = "8000"

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row("OpenCode Go", icon: "key.fill") {
                        SecureField("API キー", text: $apiKey)
                            .textContentType(.password)
                        TextField("ベース URL", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text("キーは端末の UserDefaults にのみ保存され、リポジトリには含まれません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    row("モデル", icon: "cpu.fill") {
                        TextField("チャットモデル", text: $chatModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("画像読取モデル", text: $visionModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("画像を添付したターンは画像読取モデル（mimo）が使われます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("画像生成モデル (Pollinations)", text: $imageModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Button {
                        Task { await testAPI() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(isTesting ? "テスト中..." : "API キーをテスト")
                        }
                    }
                    .disabled(isTesting || apiKey.isEmpty)
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("接続 OK") ? .green : .red)
                    }
                } header: {
                    Text("API キー動作テスト")
                }

                Section {
                    row("PC コンパニオン", icon: "desktopcomputer") {
                        TextField("PC の IP アドレス", text: $pcHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                        TextField("ポート", text: $pcPort)
                            .keyboardType(.numberPad)
                        Text("PC で pc-server/server.py を起動し、同じ WiFi に接続してください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    row("アプリ", icon: "app.badge.fill") {
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
                        LabeledContent("バージョン") {
                            Text("\(version) (\(build))")
                        }
                        LabeledContent("Bundle ID") {
                            Text(Bundle.main.bundleIdentifier ?? "-")
                        }
                    }
                }
            }
            .navigationTitle("設定")
        }
    }

    private func row(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Design.accent)
            content()
        }
        .glassCard()
        .padding(.vertical, 4)
    }

    private func testAPI() async {
        guard !apiKey.isEmpty else {
            testResult = "API キーが未設定です"
            return
        }
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let client = APIClient(baseURL: baseURL, apiKey: apiKey, model: chatModel)
            try await client.testKey()
            testResult = "接続 OK（モデル: \(chatModel)）"
        } catch {
            testResult = "失敗: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
}
