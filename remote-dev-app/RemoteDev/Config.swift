//
//  Config.swift
//  RemoteDev
//
//  アプリの設定値。API キーはここに書かず、端末の UserDefaults にのみ保存する。
//

import Foundation

enum AppConfig {
    /// OpenCode Go のデフォルトモデル
    static let defaultModel = "deepseek-v4-flash"
    /// API キーの保存キー
    static let apiKeyKey = "opencode.apiKey"
}
