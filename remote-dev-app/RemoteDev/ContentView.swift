//
//  ContentView.swift
//  RemoteDev
//
//  チャット + 設定 のタブ構成。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("チャット", systemImage: "bubble.left.and.bubble.right.fill") {
                ChatListView()
            }
            Tab("設定", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
}
