//
//  Config.swift
//  RemoteDev
//
//  アプリの設定値と既定値。API キーはリポジトリに書かず、端末の UserDefaults にのみ保存する。
//

import Foundation

enum AppConfig {
    /// 既定のチャットモデル (OpenCode Zen)
    static let defaultModel = "deepseek-v4-flash"
    /// 既定の画像生成モデル
    static let defaultImageModel = "mimo-v2.5"
    /// 既定の API ベース URL (OpenCode Go、OpenAI 互換)
    static let defaultBaseURL = "https://opencode.ai/zen/go/v1"

    static let apiKeyKey = "opencode.apiKey"
    static let baseURLKey = "opencode.baseURL"
    static let chatModelKey = "opencode.chatModel"
    static let imageModelKey = "opencode.imageModel"
    static let pcHostKey = "pc.host"
    static let pcPortKey = "pc.port"

    // ponytail: UserDefaults 平文保存。実運用では Keychain へ移す (API 実装時)。
    static var apiKey: String { UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
    static var baseURL: String { UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL }
    static var chatModel: String { UserDefaults.standard.string(forKey: chatModelKey) ?? defaultModel }
}
