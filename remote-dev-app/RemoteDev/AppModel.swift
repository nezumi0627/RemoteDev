//
//  AppModel.swift
//  RemoteDev
//
//  タブ横断で共有する会話ストアと選択タブ。
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case chat, image, pc, settings
    }

    var conversations: [Conversation] = SampleData.conversations
    var selectedTab: Tab = .chat

    /// PC から引き継いだ会話を追加/上書きしてチャットタブへ移動する
    func addHandoffConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.title == conversation.title }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        selectedTab = .chat
    }
}
