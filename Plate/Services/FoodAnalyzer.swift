import Foundation
import UIKit

/// A meal as estimated by the model or built from a database hit, before it is saved.
struct AnalyzedMeal: Equatable {
    struct Item: Equatable, Identifiable {
        var id = UUID()
        var name: String
        var quantity: Double
        var unit: String
        var gramsPerUnit: Double?
        var base: Nutrients
        var confidence: Double?

        var scaled: Nutrients { base * quantity }
        var grams: Double? { gramsPerUnit.map { $0 * quantity } }
    }

    var name: String
    var items: [Item]
    var notes: String
    var healthScore: Int?
    var confidence: Double?
    var source: MealSource
    /// True only when a model produced these numbers just now.
    ///
    /// Correcting a fresh estimate teaches something: the model guessed and was wrong. Correcting a
    /// meal repeated from the log, or taken from a barcode, teaches nothing, because those numbers
    /// were already the user's own. Source alone cannot tell the difference, since a repeat keeps the
    /// source of the meal it copied.
    var fromEstimate: Bool = true

    var totals: Nutrients { items.reduce(Nutrients.zero) { $0 + $1.scaled } }
}

/// Builds prompts for the three model-backed flows: meal photo, nutrition label photo, and text description.
struct FoodAnalyzer {
    var client = AIClient()
    /// Foods the owner never eats and the way they eat, so the estimate does not guess a chicken
    /// breast onto a vegan plate.
    var context: Context? = nil

    struct Context: Equatable {
        var diet: DietStyle
        var avoids: [String]
        /// Portions this person has corrected before, most corrected first.
        var learned: [String] = []

        init(profile: Profile) {
            diet = profile.diet
            avoids = profile.avoids
        }

        /// The few foods worth spending tokens on. Every phrase is paid for on every scan, so this is
        /// the handful that have actually been corrected rather than everything ever eaten.
        static let learnedLimit = 8

        init(profile: Profile, corrections: [FoodCorrection]) {
            self.init(profile: profile)
            learned = corrections
                .sorted { ($0.count, $0.updatedAt) > ($1.count, $1.updatedAt) }
                .prefix(Self.learnedLimit)
                .map(\.promptPhrase)
        }

        /// Appended to the request. Kept short: it is a hint, not a rule, and the photo still wins.
        var promptLine: String {
            var line = ""
            var parts: [String] = []
            if diet != .balanced { parts.append("They eat \(diet.label.lowercased()).") }
            if !avoids.isEmpty { parts.append("They do not eat: \(avoids.joined(separator: ", ")).") }
            if !parts.isEmpty {
                line += " Context about this person, useful only for choosing between equally likely foods, never for overriding what is plainly in the photo: " + parts.joined(separator: " ")
            }
            if !learned.isEmpty {
                // The wording here matters more than it looks. An earlier version said to use these
                // sizes "when one of these appears", and the model read the list as things the person
                // eats: a chicken salad came back with 300 g of rice in it, and a bowl of rice came
                // back with a chicken breast. A list of foods next to a meal is a strong suggestion
                // to include them, so the instruction has to refuse that explicitly before it says
                // anything else.
                line += " SIZE REFERENCE ONLY, NOT A LIST OF WHAT THEY ATE. The following notes say how"
                    + " big this person's usual portions are. They are not ingredients and they are not"
                    + " a meal. Never add a food to this meal because it is named here, and never"
                    + " mention one that is not actually in the meal being described. Only if a food"
                    + " below genuinely appears in this meal, and nothing in the photo or description"
                    + " contradicts it, use their usual size instead of a reference serving: "
                    + learned.joined(separator: "; ") + "."
            }
            return line
        }
    }

    private var contextLine: String { context?.promptLine ?? "" }

    /// Totals, never per unit.
    ///
    /// This used to ask for the nutrients in one unit and let the app multiply by the quantity. It
    /// produced exact answers most of the time and occasional nonsense: measured on 20 September 2026
    /// over fourteen published reference foods, three runs each, "100 g of grilled chicken breast"
    /// came back as 16,500 kcal, because the model read quantity as 100 and put the whole portion's
    /// 165 kcal in the per unit field. Mean error was 245 percent with four blowups in forty two runs.
    /// Asking for the total of what was eaten and dividing afterwards gives the app the same stored
    /// numbers and brought mean error to 3.6 percent with no blowup at all.
    static let system = """
    You are a careful registered dietitian estimating the nutrition of a single meal for a food log. \
    Break the meal into its components. List every component separately, including each fat source such as \
    butter, oil, cheese, sour cream, guacamole, dressing, and sauce, with its own realistic portion, even when it \
    is not visible; restaurant portions are larger and oilier than home cooking. Use USDA-style reference values, \
    and for named restaurant or packaged items use the published nutrition values. When a portion is uncertain, \
    choose the larger plausible amount, because people underestimate what they eat. \
    If the user supplies a correction, treat it as ground truth and re-estimate everything else around it. \
    The response keys are abbreviated to keep replies small. For each component in i: n name, q the quantity \
    eaten, u a natural unit such as cup, piece, slice, tbsp or g, g the TOTAL grams of that component, and then \
    the TOTAL nutrients for the whole amount of that component that was eaten, never per unit and never per \
    100 g: c total calories, p total protein g, cb total carbs g, f total fat g, fb total fiber g, \
    s total sugar g, so total sodium mg. If a component is 2 slices of bread, c is the calories in both slices. \
    cf is your confidence from 0 to 1. At the top level: m a short meal name like "Chicken burrito bowl", \
    cf overall confidence, h a health score from 1 to 10 for how well this meal fits a balanced diet, \
    t one plain sentence about what drove the estimate or what you could not see. \
    Round every number to at most one decimal place. Use American English and never use em dashes.
    """

    /// Added only to photo flows, because it asks the model to look at something.
    ///
    /// Portion size, not food recognition, is where the estimate actually goes wrong: the same photo
    /// asked twice came back 9.3 percent apart on average and 37 percent apart at worst. Naming real
    /// objects to measure against narrowed the worst case to 25 percent and produced shorter replies,
    /// so it costs less than it saves.
    static let photoScale = """
     Before estimating any portion, fix the scale from something of known size in the photo: a dinner \
    plate is about 27 cm across, a side plate 20 cm, a fork 19 cm, a standard mug 8 cm across the rim, \
    a slice of sandwich bread 11 cm. State the reference you used in t. Judge every portion against \
    that reference rather than by eye, and give g in grams wherever you can.
    """

    /// Every key here is billed as output tokens, once per item, on every scan. A meal with eight
    /// components carries these names ninety six times, which measured at 1,461 output tokens against
    /// 984 for the same answer under one letter keys. Output costs roughly eight times what input does,
    /// so the short names below are most of the difference between 246 and 381 scans per dollar.
    /// The meaning of each is in `parse` and must not drift from it.
    static let mealSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "m": ["type": "string"],                    // meal name
            "i": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "n": ["type": "string"],        // component name
                        "q": ["type": "number"],        // quantity eaten
                        "u": ["type": "string"],        // unit
                        "g": ["type": "number"],        // total grams
                        "c": ["type": "number"],        // total kcal
                        "p": ["type": "number"],        // total protein g
                        "cb": ["type": "number"],       // total carbs g
                        "f": ["type": "number"],        // total fat g
                        "fb": ["type": "number"],       // total fiber g
                        "s": ["type": "number"],        // total sugar g
                        "so": ["type": "number"],       // total sodium mg
                        "cf": ["type": "number"],       // confidence 0 to 1
                    ],
                    "required": ["n", "q", "u", "g", "c", "p", "cb", "f", "fb", "s", "so", "cf"],
                    "additionalProperties": false,
                ],
            ],
            "cf": ["type": "number"],                   // overall confidence
            "h": ["type": "integer"],                   // health score
            "t": ["type": "string"],                    // notes
        ],
        "required": ["m", "i", "cf", "h", "t"],
        "additionalProperties": false,
    ]

    func analyzePhoto(_ image: UIImage, hint: String = "") async throws -> AnalyzedMeal {
        var text = "Estimate the nutrition of the meal in this photo."
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            text += " The user adds: \(hint)"
        }
        text += contextLine
        let data = try await client.structured(system: Self.system + Self.photoScale,
                                               content: .init(text: text, image: image), schema: Self.mealSchema)
        return try Self.parse(data, source: .photo)
    }

    func analyzeLabel(_ image: UIImage) async throws -> AnalyzedMeal {
        let text = """
        This is a photo of a packaged food's nutrition facts label, and possibly its name. Read the label. \
        Produce exactly one item whose u is "serving", q is 1, g is the stated serving size in grams \
        (estimate if only volume is given), and whose nutrients are the per-serving values exactly as printed. \
        Name the product if visible.
        """
        // A nutrition panel is small print, and a misread number is worse than a slightly larger bill,
        // so this is the one flow that pays for full detail.
        let data = try await client.structured(system: Self.system, content: .init(text: text, image: image, imageMaxSide: 1536, detail: .high), schema: Self.mealSchema)
        return try Self.parse(data, source: .label)
    }

    func analyzeDescription(_ description: String) async throws -> AnalyzedMeal {
        let text = "Estimate the nutrition of this meal from the user's description: \(description)" + contextLine
        let data = try await client.structured(system: Self.system, content: .init(text: text), schema: Self.mealSchema)
        return try Self.parse(data, source: .describe)
    }

    /// Re-estimates a previous result with a correction from the user, such as "that was brown rice, about two cups".
    func fix(_ previous: AnalyzedMeal, image: UIImage?, correction: String) async throws -> AnalyzedMeal {
        let summary = previous.items.map { item in
            "\(item.name): \(Self.trim(item.quantity)) \(item.unit), \(Int(item.scaled.calories)) kcal"
        }.joined(separator: "; ")
        let text = """
        Your previous estimate for "\(previous.name)" was: \(summary). \
        The user corrects it: \(correction). Re-estimate the whole meal with that correction applied.
        """
        // The scale guidance only earns its tokens when there is something to look at.
        let data = try await client.structured(system: image == nil ? Self.system : Self.system + Self.photoScale,
                                               content: .init(text: text, image: image), schema: Self.mealSchema)
        var result = try Self.parse(data, source: previous.source)
        result.source = previous.source
        return result
    }

    static func parse(_ data: Data, source: MealSource) throws -> AnalyzedMeal {
        // The short names are the ones in `mealSchema`. They are terse because every one of them is
        // paid for on every scan, so they are spelled out here once rather than in the request.
        struct Raw: Decodable {
            struct Item: Decodable {
                var n: String        // name
                var q: Double        // quantity
                var u: String        // unit
                var g: Double        // grams per unit
                var c: Double        // kcal per unit
                var p: Double        // protein g
                var cb: Double       // carbs g
                var f: Double        // fat g
                var fb: Double       // fiber g
                var s: Double        // sugar g
                var so: Double       // sodium mg
                var cf: Double       // confidence
            }
            var m: String            // meal name
            var i: [Item]            // components
            var cf: Double           // overall confidence
            var h: Int               // health score
            var t: String            // notes
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw AIError.badJSON(String(decoding: data, as: UTF8.self))
        }
        let items = raw.i.map { r -> AnalyzedMeal.Item in
            // The model reports totals. The app stores per unit values so a portion can be rescaled
            // later, so divide here. A missing or zero quantity means one of whatever it described.
            let quantity = r.q > 0 ? r.q : 1
            let totals = Nutrients(calories: max(r.c, 0), protein: max(r.p, 0),
                                   carbs: max(r.cb, 0), fat: max(r.f, 0),
                                   fiber: max(r.fb, 0), sugar: max(r.s, 0),
                                   sodium: max(r.so, 0))
            let grams = r.g > 0 ? r.g : nil
            let plausible = Self.plausible(totals, grams: grams)
            return AnalyzedMeal.Item(
                name: r.n,
                quantity: quantity,
                unit: r.u,
                gramsPerUnit: grams.map { $0 / quantity },
                base: plausible.nutrients * (1 / quantity),
                // A component the arithmetic could not vouch for is pushed below the threshold that
                // makes the editor open on its portion check, so the user is asked rather than told.
                confidence: plausible.trusted ? min(max(r.cf, 0), 1) : min(r.cf, 0.4))
        }
        return AnalyzedMeal(name: raw.m, items: items, notes: raw.t,
                            healthScore: min(max(raw.h, 1), 10),
                            confidence: min(max(raw.cf, 0), 1), source: source)
    }

    /// Catches a component whose calories cannot be true of any real food.
    ///
    /// Two independent checks. Nothing edible carries more than about 9 kcal per gram, which is pure
    /// fat, so anything above that is a unit mix up rather than a rich dish. And calories are made of
    /// macros: roughly 4 per gram of protein and carbohydrate, 9 per gram of fat. When the stated
    /// calories are wildly out of step with the stated macros, the macros are the better witness,
    /// because three numbers agreeing beats one number alone.
    static let maxKcalPerGram = 9.5

    static func plausible(_ n: Nutrients, grams: Double?) -> (nutrients: Nutrients, trusted: Bool) {
        let atwater = n.protein * 4 + n.carbs * 4 + n.fat * 9
        var calories = n.calories
        var trusted = true

        if let grams, grams > 0, calories / grams > maxKcalPerGram {
            // Prefer the macros when they are themselves physically possible, otherwise fall back to
            // the densest food that could exist at this weight.
            calories = atwater > 0 && atwater / grams <= maxKcalPerGram ? atwater : grams * maxKcalPerGram
            trusted = false
        } else if atwater > 20, calories > atwater * 2.5 || calories < atwater * 0.4 {
            calories = atwater
            trusted = false
        }
        return (Nutrients(calories: calories, protein: n.protein, carbs: n.carbs, fat: n.fat,
                          fiber: n.fiber, sugar: n.sugar, sodium: n.sodium), trusted)
    }

    static func trim(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.2g", v)
    }
}
