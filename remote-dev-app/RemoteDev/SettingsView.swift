//
//  SettingsView.swift
//  RemoteDev
//
//  API / モデル / PC 接続の設定と API キー動作テスト。
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppConfig.apiKeyKey) private var apiKey = ""
    @AppStorage(AppConfig.baseURLKey) private var baseURL = AppConfig.defaultBaseURL
    @AppStorage(AppConfig.chatModelKey) private var chatModel = AppConfig.defaultModel
    @AppStorage(AppConfig.imageModelKey) private var imageModel = AppConfig.defaultImageModel
    @AppStorage(AppConfig.pcHostKey) private var pcHost = ""
    @AppStorage(AppConfig.pcPortKey) private var pcPort = "8000"

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenCode Zen") {
                    SecureField("API キー", text: $apiKey)
                        .textContentType(.password)
                    TextField("ベース URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("キーは端末の UserDefaults にのみ保存され、リポジトリには含まれません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("モデル") {
                    TextField("チャットモデル", text: $chatModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("画像生成モデル", text: $imageModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("API キー動作テスト") {
                    Button {
                        Task { await testAPI() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(isTesting ? "テスト中..." : "接続テスト")
                        }
                    }
                    .disabled(isTesting || apiKey.isEmpty)
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("接続 OK") ? .green : .red)
                    }
                }

                Section("PC コンパニオン") {
                    TextField("PC の IP アドレス", text: $pcHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                    TextField("ポート", text: $pcPort)
                        .keyboardType(.numberPad)
                    Text("PC で pc-server/server.py を起動し、同じ WiFi に接続してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("アプリ") {
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
            .navigationTitle("設定")
        }
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
