import Foundation
import UIKit

/// Which hosted model reads meal photos. Gemini has a free tier, so it is the default.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, anthropic
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .anthropic: return "Anthropic"
        }
    }
    var keyAccount: String { self == .gemini ? "gemini-api-key" : ClaudeClient.apiKeyAccount }
    var keyPlaceholder: String { self == .gemini ? "AIza..." : "sk-ant-..." }
    var host: String { self == .gemini ? "generativelanguage.googleapis.com" : "api.anthropic.com" }
    var consoleHint: String {
        switch self {
        case .gemini: return "Free: get a key at aistudio.google.com, about 250 photos a day on the free tier. Google may use free tier requests to improve its models."
        case .anthropic: return "Paid: get a key at console.anthropic.com. A photo costs about three cents with Claude Opus 5."
        }
    }

    static let defaultsKey = "aiProvider"
    static var current: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .gemini }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

enum AIError: LocalizedError {
    case missingKey(AIProvider)
    case http(Int, String)
    case refusal(String)
    case noText
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p): return "Add your \(p.label) API key in Settings to analyze food."
        case .http(let code, let body):
            if code == 401 || code == 403 { return "The API key was rejected. Check it in Settings." }
            if code == 429 { return "Rate limited. Try again in a moment." }
            if code >= 500 { return "The model service is having trouble right now. Try again shortly." }
            return "Request failed (\(code)). \(body.prefix(200))"
        case .refusal(let why): return "The model declined this request. \(why)"
        case .noText: return "No answer came back."
        case .badJSON(let s): return "Could not read the answer: \(s.prefix(120))"
        }
    }
}

/// Facade the rest of the app talks to. Picks the configured provider.
struct AIClient {
    struct Content {
        var text: String
        var image: UIImage?
    }

    var provider: AIProvider = .current

    func structured(system: String, content: Content, schema: [String: Any], maxTokens: Int = 4000) async throws -> Data {
        switch provider {
        case .gemini: return try await GeminiClient().structured(system: system, content: content, schema: schema, maxTokens: maxTokens)
        case .anthropic: return try await ClaudeClient().structured(system: system, content: .init(text: content.text, image: content.image), schema: schema, maxTokens: maxTokens)
        }
    }

    func verifyKey() async throws {
        let schema: [String: Any] = ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"], "additionalProperties": false]
        _ = try await structured(system: "Reply with ok true.", content: .init(text: "ping"), schema: schema, maxTokens: 200)
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat = 1280) -> UIImage { ClaudeClient.downscaled(image, maxSide: maxSide) }
}

/// Gemini generateContent with a JSON response schema.
struct GeminiClient {
    static let model = "gemini-2.5-flash"

    var apiKey: String? { Keychain.get(AIProvider.gemini.keyAccount) }

    func structured(system: String, content: AIClient.Content, schema: [String: Any], maxTokens: Int) async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw AIError.missingKey(.gemini) }

        var parts: [[String: Any]] = []
        if let image = content.image, let jpeg = ClaudeClient.downscaled(image).jpegData(compressionQuality: 0.82) {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        parts.append(["text": content.text])

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": Self.geminiSchema(schema),
                "maxOutputTokens": maxTokens,
                "temperature": 0.2,
            ],
        ]

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? String(decoding: data, as: UTF8.self)
            throw AIError.http(status == 400 && message.lowercased().contains("api key") ? 401 : status, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            let block = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["promptFeedback"] as? [String: Any])?["blockReason"] as? String
            throw AIError.refusal(block ?? "")
        }
        if let reason = candidate["finishReason"] as? String, reason == "SAFETY" || reason == "PROHIBITED_CONTENT" {
            throw AIError.refusal(reason.capitalized)
        }
        guard let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first else { throw AIError.noText }
        return Data(text.utf8)
    }

    /// Gemini takes an OpenAPI style schema: uppercase types, no additionalProperties.
    static func geminiSchema(_ node: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        if let type = node["type"] as? String { out["type"] = type.uppercased() }
        if let props = node["properties"] as? [String: Any] {
            out["properties"] = props.mapValues { geminiSchema($0 as? [String: Any] ?? [:]) }
        }
        if let required = node["required"] { out["required"] = required }
        if let items = node["items"] as? [String: Any] { out["items"] = geminiSchema(items) }
        if let e = node["enum"] { out["enum"] = e }
        if let d = node["description"] { out["description"] = d }
        return out
    }
}
