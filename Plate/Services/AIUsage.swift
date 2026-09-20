import Foundation

/// What the scans have cost so far.
///
/// A photo scan is not free and it is not a hundredth of a cent either. Measured on 20 September 2026,
/// a simple food lands near $0.0006 and an eight component restaurant meal near $0.0026, so a dollar
/// buys somewhere between four hundred and seventeen hundred scans depending on what is on the plate.
/// The only way to stop that being a surprise is to show it, so every reply's token counts are added
/// up here and Settings displays the running total.
enum AIUsage {
    private static let scansKey = "ai.usage.scans"
    private static let inputKey = "ai.usage.inputTokens"
    private static let outputKey = "ai.usage.outputTokens"
    private static let centsKey = "ai.usage.microCents"
    private static let sinceKey = "ai.usage.since"

    /// Dollars per million tokens, input then output, read from Google's pricing page on
    /// 20 September 2026. A model that is not listed is billed at the dearest Lite rate rather than
    /// silently counted as free, so the number shown is never lower than the truth.
    static let pricing: [String: (input: Double, output: Double)] = [
        "gemini-3.1-flash-lite": (0.25, 1.50),
        "gemini-3.1-flash-lite-preview": (0.25, 1.50),
        "gemini-3.5-flash-lite": (0.30, 2.50),
        "gemini-flash-lite-latest": (0.30, 2.50),
        "gemini-3.6-flash": (0.75, 3.75),
        "gemini-3.7-flash": (0.75, 3.75),
        "gemini-3.8-flash": (0.75, 3.75),
        "gemini-flash-latest": (0.75, 3.75),
        "gemini-3.5-flash": (1.50, 9.00),
    ]

    static func price(for model: String) -> (input: Double, output: Double) {
        pricing[model] ?? (0.30, 2.50)
    }

    /// Cost in dollars of one exchange.
    static func cost(model: String, input: Int, output: Int) -> Double {
        let rate = price(for: model)
        return Double(input) * rate.input / 1_000_000 + Double(output) * rate.output / 1_000_000
    }

    static func record(model: String, input: Int, output: Int, now: Date = Date()) {
        guard input > 0 || output > 0 else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: sinceKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: sinceKey)
        }
        defaults.set(defaults.integer(forKey: scansKey) + 1, forKey: scansKey)
        defaults.set(defaults.integer(forKey: inputKey) + input, forKey: inputKey)
        defaults.set(defaults.integer(forKey: outputKey) + output, forKey: outputKey)
        // Stored in millionths of a cent, because a single scan rounds to zero in whole cents and
        // hundreds of them would then still read as nothing.
        let microCents = Int((cost(model: model, input: input, output: output) * 100_000_000).rounded())
        defaults.set(defaults.integer(forKey: centsKey) + microCents, forKey: centsKey)
    }

    struct Summary {
        var scans: Int
        var inputTokens: Int
        var outputTokens: Int
        var dollars: Double
        var since: Date?

        var averageDollars: Double { scans > 0 ? dollars / Double(scans) : 0 }
        /// How many more scans the last dollar's worth of behaviour would buy.
        var scansPerDollar: Int? {
            guard averageDollars > 0 else { return nil }
            return Int((1 / averageDollars).rounded())
        }
    }

    static var summary: Summary {
        let defaults = UserDefaults.standard
        let since = defaults.object(forKey: sinceKey) as? Double
        return Summary(scans: defaults.integer(forKey: scansKey),
                       inputTokens: defaults.integer(forKey: inputKey),
                       outputTokens: defaults.integer(forKey: outputKey),
                       dollars: Double(defaults.integer(forKey: centsKey)) / 100_000_000,
                       since: since.map { Date(timeIntervalSince1970: $0) })
    }

    static func reset() {
        for key in [scansKey, inputKey, outputKey, centsKey, sinceKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
