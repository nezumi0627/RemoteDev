//
//  DesignSystem.swift
//  RemoteDev
//
//  アプリ全体のデザイントークンと共通部品。オーロラ壁紙 + ガラス UI の統一テーマ。
//

import SwiftUI

enum Design {
    /// オーロラ壁紙 (深い藍 → バイオレット → マゼンタ)
    static let wallpaper = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.07, blue: 0.19),
            Color(red: 0.12, green: 0.07, blue: 0.30),
            Color(red: 0.28, green: 0.08, blue: 0.35),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 自分 (ユーザー) の吹き出し: 藍 → バイオレット → ピンク
    static let userBubble = LinearGradient(
        colors: [
            Color(red: 0.39, green: 0.40, blue: 0.96),
            Color(red: 0.55, green: 0.35, blue: 0.96),
            Color(red: 0.93, green: 0.33, blue: 0.72),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = Color(red: 0.56, green: 0.42, blue: 0.98)
    static let accentSoft = Color(red: 0.85, green: 0.80, blue: 1.0)

    static let bubbleRadius: CGFloat = 20
    static let tailRadius: CGFloat = 5
    static let cardRadius: CGFloat = 18

    /// 吹き出しの角丸 (メッセージアプリ風のしっぽ付き)
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

/// 全画面共通のオーロラ壁紙 (グロー付き)
struct AuroraWallpaper: View {
    var body: some View {
        ZStack {
            Design.wallpaper
            RadialGradient(
                colors: [Design.accent.opacity(0.22), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.30, blue: 0.60).opacity(0.16), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

/// 半透明のガラスパネル (カード等)
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Design.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Design.cardRadius) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
