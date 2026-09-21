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

    /// The instructions the coach answers under.
    ///
    /// An earlier version said to answer only from the brief. That made it refuse the thing people
    /// most want from it: what should I eat next. It also made it claim not to know facts it had been
    /// given. A calorie app's assistant has to be able to use ordinary nutrition knowledge, or it is
    /// a search box over one table. What it must not do is invent facts about this person, wander off
    /// into work that has nothing to do with food, or practise medicine.
    static let system = """
    You are the assistant inside a calorie and weight tracking app, talking to its owner. You are given \
    a brief holding everything the app knows about them. Be genuinely useful about food, nutrition, \
    training and body composition.

    Two different kinds of knowledge, and the difference matters. Facts about this person come only \
    from the brief: their weight, height, targets, what they logged, how the trend is moving. Never \
    invent one, and never say you do not know something the brief plainly contains. General knowledge \
    about food and nutrition is yours to use freely: what is in a food, roughly how many calories \
    something has, which foods are high in protein, how fiber or sodium work, what a sensible meal \
    looks like. Combining the two is the whole job.

    So answer questions like these properly, with real suggestions and real numbers: what should I eat \
    next, what hits my remaining protein without going over, what is a high protein breakfast, is this \
    meal a good idea, why am I always hungry in the evening, what should I order at a restaurant, how \
    do I get more fiber. Give specific foods and rough portions, and check them against what is left \
    in their day. When you give calories or macros for a food you are suggesting, say they are \
    approximate, because they are.

    Do the arithmetic when it helps. If they have 620 kcal and 48 g of protein left, say what actually \
    fits, not that it depends.

    Respect what the brief says about how they eat. Never suggest a food they have said they avoid, and \
    keep to their way of eating unless they ask you to step outside it. Avoid the exact foods listed and \
    obvious forms of them, not the whole category they sit in: someone who does not eat shellfish can \
    still eat fish, and someone avoiding mushrooms can still eat vegetables. Refusing a whole food group \
    over one item is its own kind of unhelpful.

    Be short. Two or three sentences for most questions. A short list when a list genuinely helps, never \
    more than about six items. Lead with the answer. Use their units exactly as the brief gives them. \
    Do not restate the brief back at them, and do not pad.

    Be honest about uncertainty. A photo estimate is roughly right, not exact. A few days of data cannot \
    show a trend. Say so when it matters rather than sounding more certain than the data allows.

    Stay on this app's subject. Food, nutrition, cooking, eating out, weight, training, sleep and \
    recovery as they relate to any of that, and how to use this app. If asked for something unrelated, \
    such as writing code, doing someone's maths, drafting an email, or general trivia, say in one line \
    that this assistant is only about their food and health, and offer what you can do instead. Do not \
    attempt it anyway.

    You are not a doctor or a dietitian. Do not diagnose, do not interpret symptoms, and do not advise \
    on medication, supplements, pregnancy, or treating an eating disorder. Say plainly that it needs a \
    professional, then answer any part you can from the food side. If someone wants to eat far below the \
    floor this app sets, or describes restricting heavily, do not help with that: say why in a sentence, \
    without lecturing, and suggest talking to someone.

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

    /// `extraBurnToday` is passed in rather than read here, because only the screen holding the
    /// HealthKit snapshot knows it, and a brief that invented its own figure would be one more place
    /// for the app to disagree with itself.
    static func brief(profile: Profile, meals: [MealEntry], weights: [WeightEntry],
                      extraBurnToday: Int = 0, today: Date = Date()) -> Brief {
        var lines: [String] = []
        let units = profile.units

        lines.append("Today is \(today.formatted(date: .abbreviated, time: .omitted)).")

        // Who they are. Height was missing from this list for a while, so the coach told its owner it
        // did not know their height while the app displayed it two screens away. Anything the app
        // shows about a person belongs here.
        var about = "They are \(profile.age), \(profile.sex.label.lowercased()), "
        about += "\(Units.heightString(profile.heightCm, units)) tall, "
        about += "and weigh \(Units.weightString(profile.weightKg, units))."
        about += " Goal: \(profile.goal.label.lowercased())."
        if profile.goal.changesWeight, profile.targetWeightKg > 0 {
            about += " Aiming for \(Units.weightString(profile.targetWeightKg, units))"
            about += " at \(Units.weightString(profile.paceKgPerWeek, units, decimals: 2)) a week."
        }
        lines.append(about)

        // How they live, which is what any suggestion has to fit around.
        var habits: [String] = []
        if let activity = profile.dailyActivity { habits.append("Everyday movement: \(activity.label.lowercased()).") }
        if profile.trainingStyle != .none {
            habits.append("Trains: \(profile.trainingStyle.label.lowercased()), "
                          + "\(profile.trainingDaysPerWeek) days a week, \(profile.trainingMinutes) minutes a session.")
        } else {
            habits.append("Does not train.")
        }
        habits.append("Way of eating: \(profile.diet.label.lowercased()).")
        habits.append("Usual day: \(profile.mealPattern.label.lowercased()).")
        if !profile.avoids.isEmpty {
            habits.append("DOES NOT EAT, never suggest these: \(profile.avoids.joined(separator: ", ")).")
        }
        lines.append(habits.joined(separator: " "))
        lines.append("Baseline daily targets: \(profile.calorieTarget) kcal, \(profile.proteinTarget) g protein, "
                     + "\(profile.carbTarget) g carbs, \(profile.fatTarget) g fat, \(profile.fiberTarget) g fiber. "
                     + "Limits: \(profile.sugarLimit) g added sugar, \(profile.sodiumLimit) mg sodium.")

        // The number on the Today screen, not the baseline. Rollover and earned calories move it, and
        // quoting the baseline here made the app contradict itself by exactly the rolled over amount.
        let target = DayStats.dayTarget(profile: profile, meals: meals, day: today, extraBurn: extraBurnToday)
        var todayLine = "Today's calorie allowance is \(target.total) kcal, which is what the app shows them."
        if !target.adjustments.isEmpty {
            let parts = target.adjustments.map { "\($0.amount > 0 ? "+" : "")\($0.amount) \($0.label)" }
            todayLine += " That is the \(target.base) baseline " + parts.joined(separator: ", ") + "."
        }
        lines.append(todayLine)

        // What is left, spelled out per macro. This is the working for "what should I eat next", and
        // without it the answer can only be vague.
        let eatenToday = DayStats.totals(on: today, meals: meals)
        let left = target.total - Int(eatenToday.calories.rounded())
        func remaining(_ eaten: Double, _ goal: Int) -> String {
            let gap = goal - Int(eaten.rounded())
            return gap >= 0 ? "\(gap) g left" : "\(abs(gap)) g over"
        }
        if eatenToday.calories > 0 {
            lines.append("So far today they have eaten \(Int(eatenToday.calories.rounded())) kcal, "
                         + "\(Int(eatenToday.protein.rounded())) g protein, "
                         + "\(Int(eatenToday.carbs.rounded())) g carbs, "
                         + "\(Int(eatenToday.fat.rounded())) g fat, "
                         + "\(Int(eatenToday.fiber.rounded())) g fiber.")
            lines.append("LEFT FOR TODAY: \(left >= 0 ? "\(left) kcal" : "\(abs(left)) kcal over"), "
                         + "protein \(remaining(eatenToday.protein, profile.proteinTarget)), "
                         + "carbs \(remaining(eatenToday.carbs, profile.carbTarget)), "
                         + "fat \(remaining(eatenToday.fat, profile.fatTarget)), "
                         + "fiber \(remaining(eatenToday.fiber, profile.fiberTarget)). "
                         + "Sugar so far \(Int(eatenToday.sugar.rounded())) g of \(profile.sugarLimit) g, "
                         + "sodium \(Int(eatenToday.sodium.rounded())) mg of \(profile.sodiumLimit) mg.")
        } else {
            lines.append("Nothing logged yet today, so the whole allowance of \(target.total) kcal "
                         + "and \(profile.proteinTarget) g protein is still to come.")
        }

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
            var body = "Body fat: \(Int(bodyFat.percent.rounded())) percent, "
                + "\(bodyFat.source == .estimated ? "estimated from height and weight" : "from tape measurements")."
            let lean = profile.weightKg * (1 - bodyFat.percent / 100)
            body += " Lean mass about \(Units.weightString(lean, units))."
            lines.append(body)
        }
        if !profile.focusAreas.isEmpty {
            lines.append("Wants to change: \(profile.focusAreas.map { $0.label.lowercased() }.joined(separator: ", ")).")
        }
        lines.append("Water target \(profile.waterMl) ml a day.")

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
        var list = ["What should I eat next?",
                    "What hits my remaining protein without going over?",
                    "Where is most of my protein coming from?",
                    "What is quietly costing me the most calories?",
                    "Am I on track for my goal?"]
        if profile.goal == .lose { list.append("Why has the scale not moved this week?") }
        if profile.goal == .gain { list.append("Am I eating enough to build muscle?") }
        return list
    }
}
