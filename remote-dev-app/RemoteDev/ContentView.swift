//
//  ContentView.swift
//  RemoteDev
//
//  チャット / 画像生成 / PC同期 / 設定 の 4 タブ構成。
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        TabView(selection: $model.selectedTab) {
            Tab("チャット", systemImage: "bubble.left.and.bubble.right.fill", value: AppModel.Tab.chat) {
                ChatListView()
            }
            Tab("画像生成", systemImage: "sparkles", value: AppModel.Tab.image) {
                ImageGenView()
            }
            Tab("PC同期", systemImage: "desktopcomputer", value: AppModel.Tab.pc) {
                PCSyncView()
            }
            Tab("設定", systemImage: "gearshape.fill", value: AppModel.Tab.settings) {
                SettingsView()
            }
        }
        .tint(Design.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
