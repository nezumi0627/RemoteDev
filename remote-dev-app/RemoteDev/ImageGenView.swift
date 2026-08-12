//
//  ImageGenView.swift
//  RemoteDev
//
//  画像生成タブ (Pollinations: 無料・キー不要)。オーロラ壁紙 + ガラスカード。
//

import SwiftUI
import UIKit

struct ImageGenView: View {
    @AppStorage(AppConfig.imageModelKey) private var imageModel = AppConfig.defaultImageModel

    @State private var prompt = ""
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("画像生成")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Design.accent)
                            TextField("生成したい画像の説明（例: 夕焼けの富士山、アニメ風）", text: $prompt, axis: .vertical)
                                .lineLimit(1...4)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)

                            Button {
                                Task { await generate() }
                            } label: {
                                HStack {
                                    if isGenerating {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isGenerating ? "生成中..." : "生成（\(imageModel)）")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Design.accent)
                            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                        }
                        .glassCard()

                        if let image = generatedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

                            Button {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                status = "写真ライブラリに保存しました"
                            } label: {
                                Label("写真に保存", systemImage: "square.and.arrow.down")
                                    .font(.body.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(Design.accent)
                        }

                        if let status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status.hasPrefix("エラー") ? .red : .secondary)
                        }
                    }
                    .padding()
            }
            .navigationTitle("画像生成")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func generate() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isGenerating = true
        status = "生成中..."
        defer { isGenerating = false }
        do {
            let data = try await PollinationsClient(model: imageModel).generateImage(prompt: text)
            if let image = UIImage(data: data) {
                generatedImage = image
                status = "完了"
            } else {
                status = "エラー: 画像データを解釈できませんでした"
            }
        } catch {
            status = "エラー: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ImageGenView()
}
