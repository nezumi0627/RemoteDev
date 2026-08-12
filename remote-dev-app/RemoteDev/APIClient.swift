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

    func streamChat(messages: [APIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: makeRequest(path: "/chat/completions", body: [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
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

    // MARK: - Image generation (mimo 系は chat/completions 経由)

    func generateImage(prompt: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path: "/chat/completions", body: [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 4096,
        ]))
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.noImage }
        guard http.statusCode == 200 else {
            let msg = Self.extractErrorMessage(from: String(data: data, encoding: .utf8) ?? "")
            throw OpenAIError.http(http.statusCode, msg)
        }
        let ref = try ImageExtractor.extract(from: data)
        switch ref {
        case .data(let imageData):
            return imageData
        case .url(let url):
            let (imageData, _) = try await URLSession.shared.data(from: url)
            return imageData
        }
    }

    // MARK: - Internal

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

// MARK: - 画像抽出 (レスポンス形状は未検証のため一元化。形状違いはここで調整)

enum ImageExtractor {
    enum ImageRef: Sendable {
        case data(Data)
        case url(URL)
    }

    static func extract(from jsonData: Data) throws -> ImageRef {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) else { throw OpenAIError.noImage }
        guard let ref = findImageRef(in: obj) else { throw OpenAIError.noImage }
        return ref
    }

    private static func findImageRef(in obj: Any) -> ImageRef? {
        var result: ImageRef?
        func walk(_ value: Any) {
            if result != nil { return }
            if let s = value as? String {
                if let ref = ref(from: s) { result = ref }
            } else if let dict = value as? [String: Any] {
                for (_, v) in dict { walk(v) }
            } else if let arr = value as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(obj)
        return result
    }

    private static func ref(from raw: String) -> ImageRef? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // data URL
        if s.hasPrefix("data:image"), let comma = s.firstIndex(of: ",") {
            let b64 = s[s.index(after: comma)...]
                .prefix { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
            if let data = Data(base64Encoded: String(b64)) { return .data(data) }
        }
        // https URL (markdown ![alt](...) や裸の URL を想定。http は ATS で不可)
        if let range = s.range(of: "https://") {
            let urlStr = String(s[range.lowerBound...].prefix { !$0.isWhitespace && $0 != ")" && $0 != "\"" })
            if let url = URL(string: urlStr) { return .url(url) }
        }
        return nil
    }
}
