import Foundation

/// Answers questions about the numbers this app already holds.
///
/// The point of it is that the model never guesses about the person. Everything it is allowed to say
/// comes from a compact brief assembled here from the store: targets, the last two weeks of intake,
/// the trend line, body composition when it is known. A question is a few hundred tokens in and a few
/// hundred out, so a conversation costs a fraction of one photo scan.
///
/// What it must not do is practise medicine. The instructions below say so plainly, and the same
/// caution that governs the rest of the app applies: describe what the numbers show, name the
/// uncertainty, and send anything clinical to a professional.
struct Coach {
    var client = AIClient()

    struct Turn: Identifiable, Equatable {
        enum Role: String { case you, coach }
        let id = UUID()
        var role: Role
        var text: String
    }

    static let system = """
    You answer questions about one person's own food and weight data inside a calorie tracking app. \
    You are given a brief containing everything the app knows about them. Answer only from that brief. \
    If the brief does not contain what is needed, say which number is missing and how they would log it, \
    rather than guessing or inventing a figure. Never restate the whole brief back to them.

    Be short. Two or three sentences for most questions, a few brief lines when a list genuinely helps. \
    Lead with the answer, then the number that supports it. Use their units exactly as the brief gives them.

    Be honest about uncertainty. A photo estimate of a meal is roughly right, not exact, and a few days \
    of data cannot show a trend. Say so when it matters rather than sounding more certain than the data allows.

    You are not a doctor or a dietitian. Do not diagnose, do not interpret symptoms, and do not give advice \
    about medication, supplements, pregnancy, or eating disorders. If a question heads that way, say plainly \
    that it needs a professional and answer only the part you can from the data. If someone describes \
    restricting heavily or asks how to eat far below the floor the app sets, do not help with that; say why \
    and suggest they talk to someone.

    Use American English and never use em dashes.
    """

    static let answerSchema: [String: Any] = [
        "type": "object",
        "properties": ["a": ["type": "string"]],
        "required": ["a"],
        "additionalProperties": false,
    ]

    /// Everything the model is allowed to know, kept deliberately small.
    struct Brief {
        var lines: [String]

        var text: String { lines.joined(separator: "\n") }
    }

    static func brief(profile: Profile, meals: [MealEntry], weights: [WeightEntry],
                      today: Date = Date()) -> Brief {
        var lines: [String] = []
        let units = profile.units

        lines.append("Today is \(today.formatted(date: .abbreviated, time: .omitted)).")

        // Who they are and what they asked the app for.
        var about = "They are \(profile.age) and \(profile.sex.label.lowercased())."
        about += " Goal: \(profile.goal.label.lowercased())."
        lines.append(about)
        lines.append("Daily targets: \(profile.calorieTarget) kcal, \(profile.proteinTarget) g protein, "
                     + "\(profile.carbTarget) g carbs, \(profile.fatTarget) g fat, \(profile.fiberTarget) g fiber.")

        // Weight and where it is going, which is the question most people actually have.
        let samples = weights.map { TrendEngine.Sample(date: $0.date, weightKg: $0.weightKg) }
        let points = TrendEngine.trend(samples)
        if let trend = TrendEngine.latestTrend(points) {
            lines.append("Trend weight: \(Units.weightString(trend, units)). Scale weight last logged: "
                         + "\(Units.weightString(profile.weightKg, units)).")
        }
        if let rate = TrendEngine.weeklyRate(points) {
            let direction = rate < 0 ? "down" : "up"
            lines.append("Over the last three weeks the trend is \(direction) "
                         + "\(Units.weightString(abs(rate), units, decimals: 2)) a week.")
        } else {
            lines.append("Not enough weigh ins yet to show a trend.")
        }

        if let bodyFat = profile.bodyFat {
            lines.append("Body fat: \(Int(bodyFat.percent.rounded())) percent, "
                         + "\(bodyFat.source == .estimated ? "estimated from height and weight" : "from tape measurements").")
        }

        // Two weeks of intake. Days with nothing logged are stated as gaps rather than zeros, because
        // a zero would read as fasting and skew anything the model says about averages.
        let daily = DayStats.dailyCalories(meals: meals, days: 14, endingOn: today)
        let logged = daily.compactMap { $0.1 }
        if logged.isEmpty {
            lines.append("Nothing logged in the last 14 days.")
        } else {
            let average = logged.reduce(0, +) / Double(logged.count)
            lines.append("Logged on \(logged.count) of the last 14 days, averaging "
                         + "\(Int(average.rounded())) kcal on the days they logged.")
            // Each day carries its own name. An unlabelled list invites the model to count backwards
            // and answer "how much did I eat on Tuesday" with the wrong day, which it did.
            let named = DateFormatter()
            named.dateFormat = "EEE d MMM"
            let recent = daily.suffix(7)
                .map { day, kcal in
                    "\(named.string(from: day)) \(kcal.map { "\(Int($0.rounded())) kcal" } ?? "nothing logged")"
                }
                .joined(separator: "; ")
            lines.append("Last 7 days: \(recent).")
        }

        // Yesterday in full, because "how did I do" usually means yesterday.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let y = DayStats.totals(on: yesterday, meals: meals)
        if y.calories > 0 {
            lines.append("Yesterday: \(Int(y.calories.rounded())) kcal, \(Int(y.protein.rounded())) g protein, "
                         + "\(Int(y.carbs.rounded())) g carbs, \(Int(y.fat.rounded())) g fat, "
                         + "\(Int(y.fiber.rounded())) g fiber, \(Int(y.sugar.rounded())) g sugar, "
                         + "\(Int(y.sodium.rounded())) mg sodium.")
        }

        // What they actually eat, which is the only way to answer "where is my protein coming from".
        let window = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
        let items = meals.filter { $0.date >= window }.flatMap { $0.items }
        if !items.isEmpty {
            let byProtein = Dictionary(grouping: items, by: { $0.name })
                .mapValues { $0.reduce(0.0) { $0 + $1.scaled.protein } }
                .sorted { $0.value > $1.value }.prefix(6)
            lines.append("Biggest protein sources over 14 days: "
                         + byProtein.map { "\($0.key) \(Int($0.value.rounded())) g" }.joined(separator: ", ") + ".")
            let byCalories = Dictionary(grouping: items, by: { $0.name })
                .mapValues { $0.reduce(0.0) { $0 + $1.scaled.calories } }
                .sorted { $0.value > $1.value }.prefix(6)
            lines.append("Biggest calorie sources over 14 days: "
                         + byCalories.map { "\($0.key) \(Int($0.value.rounded())) kcal" }.joined(separator: ", ") + ".")
        }

        lines.append("Logging streak: \(DayStats.streak(meals: meals, today: today)) days.")
        return Brief(lines: lines)
    }

    /// The last few turns only. A long history would cost more than the answer is worth, and this is a
    /// question and answer tool rather than a conversation that needs to remember last week.
    static func transcript(_ turns: [Turn], keeping: Int = 6) -> String {
        turns.suffix(keeping)
            .map { "\($0.role == .you ? "Question" : "Answer"): \($0.text)" }
            .joined(separator: "\n")
    }

    func answer(question: String, brief: Brief, history: [Turn]) async throws -> String {
        var text = "Here is everything known about this person.\n\n\(brief.text)\n\n"
        let past = Self.transcript(history)
        if !past.isEmpty { text += "Earlier in this conversation:\n\(past)\n\n" }
        text += "Their question: \(question)"

        let data = try await client.structured(system: Self.system,
                                               content: .init(text: text),
                                               schema: Self.answerSchema,
                                               maxTokens: 700)
        struct Raw: Decodable { var a: String }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
            throw AIError.badJSON(String(decoding: data, as: UTF8.self))
        }
        return raw.a.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Openers worth tapping, chosen so each one is answerable from the brief.
    static func suggestions(profile: Profile, hasMeals: Bool) -> [String] {
        guard hasMeals else {
            return ["What should I log first?",
                    "How did you work out my calorie target?",
                    "Why does the trend line matter more than the scale?"]
        }
        var list = ["Where is most of my protein coming from?",
                    "What is quietly costing me the most calories?",
                    "Am I on track for my goal?"]
        if profile.goal == .lose { list.append("Why has the scale not moved this week?") }
        if profile.goal == .gain { list.append("Am I eating enough to build muscle?") }
        return list
    }
}
