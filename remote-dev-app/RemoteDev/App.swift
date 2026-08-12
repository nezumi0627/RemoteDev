//
//  App.swift
//  RemoteDev
//
//  RemoteDev 本体。OpenCode Zen と会話し、PC コンパニオンと同期するチャットアプリ。
//

import SwiftUI

@main
struct RemoteDevApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
