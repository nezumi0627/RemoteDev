//
//  APIClient.swift
//  RemoteDev
//
//  OpenCode Zen (OpenAI 互換) へのチャット/画像生成と、PC コンパニオンへのアクセス。
//

import Foundation

struct APIMessage: Sendable {
    let role: String
    let content: String
    let images: [Data]

    init(role: String, content: String, images: [Data] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

enum OpenAIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case noContent
    case noImage

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL が不正です"
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        case .noContent: return "応答にテキストがありません"
        case .noImage: return "画像を生成できませんでした"
        }
    }
}

struct APIClient {
    let baseURL: String
    let apiKey: String
    let model: String
    var timeout: TimeInterval = 600

    private var headers: [String: String] {
        ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"]
    }

    // MARK: - Chat (SSE streaming)

    func streamChat(messages: [APIMessage], allowImages: Bool) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: makeRequest(path: "/chat/completions", body: [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { Self.messageBody($0, allowImages: allowImages) },
                    ]))
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let msg = await Self.readErrorBody(bytes: bytes)
                        continuation.finish(throwing: OpenAIError.http(status, msg))
                        return
                    }
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]" else { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// API キーの動作確認 (最小の非ストリーム呼び出し)
    func testKey() async throws {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path: "/chat/completions", body: [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1,
        ]))
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.noContent }
        guard http.statusCode == 200 else {
            let msg = Self.extractErrorMessage(from: String(data: data, encoding: .utf8) ?? "")
            throw OpenAIError.http(http.statusCode, msg)
        }
    }

    // MARK: - Internal

    /// メッセージ本文を構築。画像は allowImages (mimo ターン) のときだけ image_url として付ける。
    /// text モデル (deepseek) は image_url を拒否するため、ここで確実に除去する。
    private static func messageBody(_ message: APIMessage, allowImages: Bool) -> [String: Any] {
        let images = allowImages ? message.images : []
        guard !images.isEmpty else {
            return ["role": message.role, "content": message.content]
        }
        var parts: [[String: Any]] = []
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        for image in images {
            parts.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image.base64EncodedString())"]])
        }
        return ["role": message.role, "content": parts]
    }

    private func makeRequest(path: String, body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw OpenAIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func readErrorBody(bytes: URLSession.AsyncBytes) async -> String {
        var body = ""
        do {
            for try await line in bytes.lines {
                body += line
                if body.count > 3000 { break }
            }
        } catch {
            return ""
        }
        return extractErrorMessage(from: body)
    }

    static func extractErrorMessage(from body: String) -> String {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = obj["error"] as? [String: Any],
           let msg = error["message"] as? String {
            return msg
        }
        return String(body.prefix(200))
    }
}

// MARK: - PC companion client

struct PCClient {
    let baseURL: String

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw OpenAIError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.noContent }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(http.statusCode, String(msg.prefix(120)))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - 画像生成 (Pollinations: 無料・キー不要。OpenCode Go は画像出力非対応のため)

struct PollinationsClient {
    var model: String

    func generateImage(prompt: String, width: Int = 1024, height: Int = 1024) async throws -> Data {
        var components = URLComponents(string: "https://image.pollinations.ai/prompt/")
        let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? prompt
        components?.path.append(encoded)
        components?.queryItems = [
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "nologo", value: "true"),
            URLQueryItem(name: "model", value: model),
        ]
        guard let url = components?.url else { throw OpenAIError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "画像サービスエラー")
        }
        return data
    }
}
