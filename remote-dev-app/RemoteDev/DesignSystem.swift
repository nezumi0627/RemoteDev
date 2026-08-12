//
//  DesignSystem.swift
//  RemoteDev
//
//  アプリ全体のデザイントークン。シンプルでフラットな iMessage 風の美しさを目指す。
//

import SwiftUI

enum Design {
    /// アクセント: クリーンな青
    static let accent = Color(red: 0.20, green: 0.47, blue: 0.95)

    /// 自分 (ユーザー) の吹き出し色 (フラット)
    static let userBubble = Color(red: 0.20, green: 0.47, blue: 0.95)

    /// 相手 (アシスタント) の吹き出し色 (薄いグレー)
    static let assistantBubble = Color(uiColor: .systemGray5)

    static let bubbleRadius: CGFloat = 20
    static let tailRadius: CGFloat = 5
    static let cardRadius: CGFloat = 14

    /// 吹き出しの角丸 (しっぽ付き)
    static func bubbleShape(isUser: Bool, isFirst: Bool, isLast: Bool) -> UnevenRoundedRectangle {
        if isUser {
            return UnevenRoundedRectangle(
                topLeadingRadius: bubbleRadius,
                bottomLeadingRadius: bubbleRadius,
                bottomTrailingRadius: isLast ? tailRadius : bubbleRadius,
                topTrailingRadius: isFirst ? bubbleRadius : tailRadius
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: isFirst ? bubbleRadius : tailRadius,
                bottomLeadingRadius: isLast ? tailRadius : bubbleRadius,
                bottomTrailingRadius: bubbleRadius,
                topTrailingRadius: bubbleRadius
            )
        }
    }
}

/// 薄いカード (システム背景色ベース)
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Design.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Design.cardRadius) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
