//
//  SettingsView.swift
//  RemoteDev
//
//  モデル選択と API キー設定。キーは端末内のみに保存。
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppConfig.apiKeyKey) private var apiKey = ""
    private let model = AppConfig.defaultModel

    var body: some View {
        NavigationStack {
            Form {
                Section("モデル") {
                    LabeledContent("デフォルト") {
                        Text(model)
                    }
                }

                Section("OpenCode Go API") {
                    SecureField("API キー", text: $apiKey)
                        .textContentType(.password)
                    Text("キーは端末の UserDefaults にのみ保存され、リポジトリには含まれません。")
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
}

#Preview {
    SettingsView()
}
