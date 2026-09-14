import Foundation
import UIKit

/// Minimal client for the Anthropic Messages API. Only the pieces Plate needs:
/// vision input, structured JSON output, adaptive thinking.
struct ClaudeClient {
    static let apiKeyAccount = "anthropic-api-key"
    static let modelDefaultsKey = "claudeModel"
    static let defaultModel = "claude-opus-5"
    static let models: [(id: String, label: String, note: String)] = [
        ("claude-opus-5", "Claude Opus 5", "Best accuracy, about 3 cents per photo"),
        ("claude-sonnet-5", "Claude Sonnet 5", "Faster and cheaper, about 1 cent per photo"),
    ]

    var apiKey: String? { Keychain.get(Self.apiKeyAccount) }
    var model: String { UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? Self.defaultModel }

    struct Content {
        var text: String
        var image: UIImage?
    }

    /// Sends one user turn and returns the JSON text the model produced for `schema`.
    func structured(system: String, content: Content, schema: [String: Any], maxTokens: Int = 4000) async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw AIError.missingKey(.anthropic) }

        var blocks: [[String: Any]] = []
        if let image = content.image, let jpeg = Self.downscaled(image).jpegData(compressionQuality: 0.82) {
            blocks.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ])
        }
        blocks.append(["type": "text", "text": content.text])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": blocks]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? String(decoding: data, as: UTF8.self)
            throw AIError.http(status, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badJSON(String(decoding: data, as: UTF8.self))
        }
        if json["stop_reason"] as? String == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw AIError.refusal(details?["explanation"] as? String ?? "")
        }
        guard let contentBlocks = json["content"] as? [[String: Any]],
              let text = contentBlocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw AIError.noText }
        return Data(text.utf8)
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat = 1280) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
