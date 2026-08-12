//
//  Config.swift
//  RemoteDev
//
//  アプリの設定値と既定値。API キーはリポジトリに書かず、端末の UserDefaults にのみ保存する。
//

import Foundation

enum AppConfig {
    /// 既定のチャットモデル (OpenCode Go)
    static let defaultModel = "deepseek-v4-flash"
    /// 画像付きターンで使うモデル (Go は mimo のみ画像入力対応)
    static let defaultVisionModel = "mimo-v2.5"
    /// 画像生成の既定モデル (Pollinations: 無料・キー不要)
    static let defaultImageModel = "flux"
    /// 既定の API ベース URL (OpenCode Go、OpenAI 互換)
    static let defaultBaseURL = "https://opencode.ai/zen/go/v1"

    static let apiKeyKey = "opencode.apiKey"
    static let baseURLKey = "opencode.baseURL"
    static let chatModelKey = "opencode.chatModel"
    static let visionModelKey = "opencode.visionModel"
    static let imageModelKey = "opencode.imageModel.v2"
    static let pcHostKey = "pc.host"
    static let pcPortKey = "pc.port"

    /// チャットタブで選べる Go のモデル候補
    static let goChatModels = [
        "deepseek-v4-flash", "deepseek-v4-pro", "glm-5.2", "kimi-k3",
        "qwen3.7-max", "minimax-m3", "gpt-5.6-luna",
    ]

    // ponytail: UserDefaults 平文保存。実運用では Keychain へ移す。
    static var apiKey: String { UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
    static var baseURL: String { UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL }
    static var chatModel: String { UserDefaults.standard.string(forKey: chatModelKey) ?? defaultModel }
    static var imageVisionModel: String { UserDefaults.standard.string(forKey: visionModelKey) ?? defaultVisionModel }

    static func setChatModel(_ model: String) {
        UserDefaults.standard.set(model, forKey: chatModelKey)
    }
}
