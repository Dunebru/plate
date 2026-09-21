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
        case .gemini: return "Free: get a key at aistudio.google.com. Plate uses Flash-Lite, the fastest and cheapest model. The free tier allows about 20 scans a day per model and Plate moves to the next model when one runs out; with billing on, $10 covers roughly 5,000 scans. Google may use free tier requests to improve its models."
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
    case truncated
    case noModel(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p): return "Add your \(p.label) API key in Settings to analyze food."
        case .http(let code, let body):
            if code == 401 || code == 403 { return "The API key was rejected. Check it in Settings." }
            if code == 429 { return body.lowercased().contains("quota") ? "The free limit for this key is used up for now. Wait a minute and try again, or log this meal by barcode, search, or description." : "Too many requests. Try again in a moment." }
            if code >= 500 { return "The model service is busy right now. Try again in a moment." }
            return "Request failed (\(code)). \(body.prefix(200))"
        case .refusal(let why): return "The model declined this request. \(why)"
        case .noText: return "No answer came back."
        case .truncated: return "The answer was cut off. Try again, or describe the meal in fewer words."
        case .noModel(let why): return "No Gemini model is available for this key right now. \(why.prefix(160))"
        case .badJSON(let s): return "Could not read the answer: \(s.prefix(120))"
        }
    }
}

/// Facade the rest of the app talks to. Picks the configured provider.
struct AIClient {
    /// How much of the token budget an image is allowed to spend. Measured on 20 September 2026 with
    /// countTokens: an image costs 1,064 tokens at the default, 540 at medium and 266 at low, and the
    /// pixel size sent makes no difference to any of them.
    enum ImageDetail {
        case low, medium, high

        var geminiValue: String? {
            switch self {
            case .low: return "MEDIA_RESOLUTION_LOW"
            case .medium: return "MEDIA_RESOLUTION_MEDIUM"
            case .high: return nil          // the API default
            }
        }
    }

    struct Content {
        var text: String
        var image: UIImage?
        /// Longest edge of the uploaded image. Gemini charges the same tokens for anything above
        /// roughly a thousand pixels, so this only decides how many bytes go up the wire.
        var imageMaxSide: CGFloat = 1280
        /// Low, because detail turned out not to matter for food. Measured on 20 September 2026 over
        /// eight real meal photos, five runs each: the same photo at the same setting varies by 9.3
        /// percent on average, while low differs from full detail by only 3.7 percent. The difference
        /// between settings is smaller than the model's own run to run wobble about portion size, so
        /// paying for more pixels buys nothing. Nutrition labels are the exception and ask for full
        /// detail, because a misread number there is worse than a slightly larger bill.
        var detail: ImageDetail = .low
    }

    var provider: AIProvider = .current

    func structured(system: String, content: Content, schema: [String: Any], maxTokens: Int = 4000) async throws -> Data {
        switch provider {
        case .gemini: return try await GeminiClient().structured(system: system, content: content, schema: schema, maxTokens: maxTokens)
        case .anthropic: return try await ClaudeClient().structured(system: system, content: .init(text: content.text, image: content.image, imageMaxSide: content.imageMaxSide), schema: schema, maxTokens: maxTokens)
        }
    }

    func verifyKey() async throws {
        let schema: [String: Any] = ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"], "additionalProperties": false]
        _ = try await structured(system: "Reply with ok true.", content: .init(text: "ping"), schema: schema, maxTokens: 200)
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat = 1280) -> UIImage { ClaudeClient.downscaled(image, maxSide: maxSide) }
}

/// Gemini generateContent with a JSON response schema.
///
/// Google retires model names every few months, so nothing here depends on a single one: a short
/// list is tried in order, the account's own model list is the last resort, and whichever model
/// answers is remembered for next time.
struct GeminiClient {
    /// Lite models only, cheapest first. Benchmarked on 20 September 2026 over fourteen published
    /// reference foods, three runs each, with the totals prompt in FoodAnalyzer: 3.1 Flash-Lite
    /// averaged 3.6 percent off with no estimate more than 50 percent out, at $0.25 and $1.50 per
    /// million tokens. 3.5 Flash-Lite averaged 4.8 percent with one miss at 80 percent and costs
    /// $0.30 and $2.50. The cheaper model was also the more accurate one, so it leads.
    ///
    /// The full size Flash models used to sit at the end of this list as a fallback. They are gone on
    /// purpose. 3.5 Flash bills output at $9 per million, thirteen times Lite's rate before any
    /// thinking tokens, and falling back to it silently turned a busy minute into a bill nobody asked
    /// for. When every Lite model is busy the scan now fails and can be retried, which costs nothing.
    ///
    /// 2.5 Flash-Lite is cheaper still on paper, at $0.10 and $0.40, and it is the only Lite model
    /// that can switch thinking off entirely. It is not here because it does not work: a key made in
    /// September 2026 gets 404 "no longer available to new users" from it and from 2.5 Flash, even
    /// though both are still listed as current. The alias is last as a hedge against renames; it
    /// resolved to 3.5 Flash-Lite when this was written.
    static let preferred = ["gemini-3.1-flash-lite", "gemini-3.5-flash-lite", "gemini-flash-lite-latest"]
    static let modelDefaultsKey = "gemini.model"
    /// Thinking tokens the service reported for the latest answer. Zero means the speed hint took effect.
    nonisolated(unsafe) static var lastThoughtTokens = 0
    private static let base = "https://generativelanguage.googleapis.com/v1beta"

    static var rememberedModel: String? {
        get { UserDefaults.standard.string(forKey: modelDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: modelDefaultsKey) }
    }

    /// Set by tests; the app always reads the keychain.
    var keyOverride: String?
    var apiKey: String? { keyOverride ?? Keychain.get(AIProvider.gemini.keyAccount) }

    /// The remembered model first, then the preferred list, without repeats. Models that recently
    /// said they were busy go to the back, so a scan does not pay for a refusal it can predict.
    static func candidates(remembered: String?, now: Date = Date()) -> [String] {
        var seen = Set<String>()
        let ordered = ([remembered].compactMap { $0 } + preferred).filter { seen.insert($0).inserted }
        return ordered.filter { !isCoolingDown($0, now: now) } + ordered.filter { isCoolingDown($0, now: now) }
    }

    private static func cooldownKey(_ model: String) -> String { "gemini.busyUntil.\(model)" }

    static func isCoolingDown(_ model: String, now: Date = Date()) -> Bool {
        UserDefaults.standard.double(forKey: cooldownKey(model)) > now.timeIntervalSince1970
    }

    /// How long to steer around a busy model. A daily quota only returns at midnight Pacific, even
    /// though the error also says "retry in 40s"; a rate limit says how long to wait; plain overload
    /// usually clears within a minute.
    static func cooldown(status: Int, message: String, now: Date = Date()) -> TimeInterval {
        let m = message.lowercased()
        if status == 429, m.contains("perday") || m.contains("per day") { return secondsUntilPacificMidnight(from: now) }
        if let r = m.range(of: #"retry in ([0-9.]+)\s*s"#, options: .regularExpression),
           let secs = Double(m[r].dropFirst("retry in ".count).filter { $0.isNumber || $0 == "." }) { return min(max(secs, 15), 600) }
        return status == 429 ? 120 : 45
    }

    static func secondsUntilPacificMidnight(from now: Date) -> TimeInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let next = cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        return max(60, next.timeIntervalSince(now))
    }

    static func markBusy(_ model: String, status: Int, message: String, now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970 + cooldown(status: status, message: message, now: now), forKey: cooldownKey(model))
    }

    enum Verdict: Equatable {
        case gone     // this model name no longer works for this key: skip it and stop preferring it
        case busy     // overloaded or out of quota right now: another model may answer, keep the preference
        case fatal    // bad key or bad request: no other model will help
    }

    /// Each model has its own capacity and its own free tier quota, so a busy model is a reason to
    /// try the next one rather than to fail the scan.
    static func verdict(status: Int, message: String) -> Verdict {
        let m = message.lowercased()
        let gonePhrases = ["no longer available", "is not found", "not found for api version", "is not supported", "is not available"]
        let noFreeTier = m.range(of: #"limit: 0(\D|$)"#, options: .regularExpression) != nil   // this model has no free allowance at all
        if status == 404 || ([400, 403, 429].contains(status) && (noFreeTier || gonePhrases.contains { m.contains($0) })) { return .gone }
        if status == 429 || (500...599).contains(status) { return .busy }
        return .fatal
    }

    /// Picks general purpose Flash models out of a ListModels answer: Lite first because it is the
    /// fastest and cheapest, newest version first within each group.
    static func rankDiscovered(_ models: [(name: String, methods: [String])]) -> [String] {
        let skip = ["image", "tts", "live", "audio", "embedding", "native", "preview", "exp", "omni"]
        func version(_ n: String) -> Double {
            let digits = n.replacingOccurrences(of: "gemini-", with: "").prefix { $0.isNumber || $0 == "." }
            return Double(digits) ?? 0
        }
        let usable = models
            .filter { $0.methods.contains("generateContent") }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { n in n.hasPrefix("gemini-") && n.contains("flash") && !skip.contains { n.contains($0) } }
        let lite = usable.filter { $0.contains("lite") }.sorted { version($0) > version($1) }
        let full = usable.filter { !$0.contains("lite") }.sorted { version($0) > version($1) }
        return lite + full
    }

    /// Reading a plate does not need long deliberation, and thinking is most of the wait. "minimal" is
    /// the one setting every current Flash and Flash-Lite model accepts; Lite rejects a zero budget.
    static let thinkingConfig: [String: Any] = ["thinkingLevel": "minimal"]

    /// A model that does not take the thinking setting often answers with a bare "invalid argument",
    /// so any 400 sent with the hint is worth exactly one try without it. A 400 about the key is
    /// reported as 401 before it gets here.
    static func isThinkingRejected(status: Int, message: String) -> Bool { status == 400 }

    private static func hintRejectedKey(_ model: String) -> String { "gemini.noThinkingHint.\(model)" }

    func structured(system: String, content: AIClient.Content, schema: [String: Any], maxTokens: Int) async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw AIError.missingKey(.gemini) }

        var parts: [[String: Any]] = []
        if let image = content.image, let jpeg = ClaudeClient.downscaled(image, maxSide: content.imageMaxSide).jpegData(compressionQuality: 0.82) {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        parts.append(["text": content.text])

        // Thinking is switched off below, but a model that ignores the hint spends thinking tokens
        // from the same allowance and they are billed as output. The ceiling is therefore the most
        // a single scan can ever cost, so it is set just above what a large meal actually needs:
        // an eight component meal measured at 984 output tokens.
        let budget = min(max(maxTokens, 1600), 2400)
        var tried: [String] = []
        var lastError: AIError = .noModel("")
        var sawBusy = false
        var busyCount = 0
        var gone = Set<String>()
        let natural = Self.candidates(remembered: Self.rememberedModel, now: .distantFuture)   // preference order, cooldowns ignored

        func attempt(_ model: String) async throws -> Data? {
            tried.append(model)
            do {
                let data: Data
                do { data = try await send(model: model, key: key, system: system, parts: parts, schema: schema, maxTokens: budget, detail: content.detail) }
                // One retry with more room, not three times more: the old multiplier meant a model
                // that ignored the thinking hint could spend twelve thousand output tokens on one
                // photo, and it re-sent the image to do it.
                catch AIError.truncated { data = try await send(model: model, key: key, system: system, parts: parts, schema: schema, maxTokens: 4000, detail: content.detail) }
                // Adopt this model as the favorite only when every better one is really gone, not when
                // they were busy or sitting out a cooldown. Otherwise one bad minute would demote the
                // best model for good.
                let better = natural.prefix { $0 != model }
                if better.allSatisfy({ gone.contains($0) }) { Self.rememberedModel = model }
                return data
            } catch AIError.http(let status, let message) {
                switch Self.verdict(status: status, message: message) {
                case .fatal: throw AIError.http(status, message)
                case .gone:
                    gone.insert(model)
                    lastError = .noModel(message)
                    if Self.rememberedModel == model { Self.rememberedModel = nil }
                case .busy:
                    lastError = .http(status, message)
                    sawBusy = true
                    busyCount += 1
                    Self.markBusy(model, status: status, message: message)
                }
                return nil
            }
        }

        for model in Self.candidates(remembered: Self.rememberedModel) where busyCount < 3 {
            if let data = try await attempt(model) { return data }
        }
        if !sawBusy {
            for model in (try? await discover(key: key)) ?? [] where !tried.contains(model) && busyCount < 3 {
                if let data = try await attempt(model) { return data }
            }
        }
        throw lastError
    }

    /// Asks the API which models this key can use.
    func discover(key: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(Self.base)/models?pageSize=200")!)
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (data, _) = try await URLSession.shared.data(for: request)
        let list = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["models"] as? [[String: Any]] ?? []
        return Self.rankDiscovered(list.map { (name: $0["name"] as? String ?? "", methods: $0["supportedGenerationMethods"] as? [String] ?? []) })
    }

    private func send(model: String, key: String, system: String, parts: [[String: Any]], schema: [String: Any], maxTokens: Int, detail: AIClient.ImageDetail) async throws -> Data {
        let rejectedKey = Self.hintRejectedKey(model)
        if !UserDefaults.standard.bool(forKey: rejectedKey) {
            do { return try await post(model: model, key: key, system: system, parts: parts, schema: schema, maxTokens: maxTokens, hint: true, detail: detail) }
            catch AIError.http(let status, let message) where Self.isThinkingRejected(status: status, message: message) {
                // Only blame the hint if the same request succeeds without it.
                let data = try await post(model: model, key: key, system: system, parts: parts, schema: schema, maxTokens: maxTokens, hint: false, detail: detail)
                UserDefaults.standard.set(true, forKey: rejectedKey)
                return data
            }
        }
        return try await post(model: model, key: key, system: system, parts: parts, schema: schema, maxTokens: maxTokens, hint: false, detail: detail)
    }

    private func post(model: String, key: String, system: String, parts: [[String: Any]], schema: [String: Any], maxTokens: Int, hint: Bool, detail: AIClient.ImageDetail) async throws -> Data {
        var config: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": Self.geminiSchema(schema),
            "maxOutputTokens": maxTokens,
            "temperature": 0.2,
        ]
        if hint { config["thinkingConfig"] = Self.thinkingConfig }
        // Only meaningful when a part carries an image, and harmless otherwise.
        if let resolution = detail.geminiValue { config["mediaResolution"] = resolution }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": config,
        ]

        var request = URLRequest(url: URL(string: "\(Self.base)/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0["error"] as? [String: Any] }
            var message = error?["message"] as? String ?? String(decoding: data, as: UTF8.self)
            // Whether a quota is per minute or per day is only stated in the details.
            let quotaIds = (error?["details"] as? [[String: Any]] ?? [])
                .flatMap { $0["violations"] as? [[String: Any]] ?? [] }
                .compactMap { $0["quotaId"] as? String }
            if !quotaIds.isEmpty { message += " [" + quotaIds.joined(separator: ", ") + "]" }
            throw AIError.http(status == 400 && message.lowercased().contains("api key") ? 401 : status, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            let block = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["promptFeedback"] as? [String: Any])?["blockReason"] as? String
            throw AIError.refusal(block ?? "")
        }
        let usage = json["usageMetadata"] as? [String: Any]
        Self.lastThoughtTokens = usage?["thoughtsTokenCount"] as? Int ?? 0
        AIUsage.record(model: model,
                       input: usage?["promptTokenCount"] as? Int ?? 0,
                       output: (usage?["candidatesTokenCount"] as? Int ?? 0) + Self.lastThoughtTokens)
        let reason = candidate["finishReason"] as? String ?? ""
        if reason == "SAFETY" || reason == "PROHIBITED_CONTENT" { throw AIError.refusal(reason.capitalized) }
        let text = ((candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]])?
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }.joined() ?? ""
        if reason == "MAX_TOKENS" { throw AIError.truncated }
        guard !text.isEmpty else { throw AIError.noText }
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
