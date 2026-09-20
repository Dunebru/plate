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

    var totals: Nutrients { items.reduce(Nutrients.zero) { $0 + $1.scaled } }
}

/// Builds prompts for the three model-backed flows: meal photo, nutrition label photo, and text description.
struct FoodAnalyzer {
    var client = AIClient()

    static let system = """
    You are a careful registered dietitian estimating the nutrition of a single meal for a food log. \
    Break the meal into its components. For each component give the portion you believe was eaten \
    (quantity and a natural unit such as cup, piece, slice, tbsp, or g), your best estimate of grams per unit, \
    and the nutrients PER ONE UNIT, not for the whole portion. Calories in kcal, protein, carbs, fat, fiber and \
    sugar in grams, sodium in milligrams. List every component separately, including each fat source such as \
    butter, oil, cheese, sour cream, guacamole, dressing, and sauce, with its own realistic portion, even when it \
    is not visible; restaurant portions are larger and oilier than home cooking. Use USDA-style reference values, \
    and for named restaurant or packaged items use the published nutrition values. When a portion is uncertain, \
    choose the larger plausible amount, because people underestimate what they eat. \
    If the user supplies a correction, treat it as ground truth and re-estimate everything else around it. \
    Report confidence from 0 to 1 per item and overall. meal_name is short, like "Chicken burrito bowl". \
    health_score is 1 to 10 for how well this meal fits a balanced diet. notes is one plain sentence about \
    what drove the estimate or what you could not see. Use American English and never use em dashes.
    """

    static let mealSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "meal_name": ["type": "string"],
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "quantity": ["type": "number"],
                        "unit": ["type": "string"],
                        "grams_per_unit": ["type": "number"],
                        "calories_per_unit": ["type": "number"],
                        "protein_g_per_unit": ["type": "number"],
                        "carbs_g_per_unit": ["type": "number"],
                        "fat_g_per_unit": ["type": "number"],
                        "fiber_g_per_unit": ["type": "number"],
                        "sugar_g_per_unit": ["type": "number"],
                        "sodium_mg_per_unit": ["type": "number"],
                        "confidence": ["type": "number"],
                    ],
                    "required": ["name", "quantity", "unit", "grams_per_unit", "calories_per_unit", "protein_g_per_unit",
                                 "carbs_g_per_unit", "fat_g_per_unit", "fiber_g_per_unit", "sugar_g_per_unit",
                                 "sodium_mg_per_unit", "confidence"],
                    "additionalProperties": false,
                ],
            ],
            "confidence": ["type": "number"],
            "health_score": ["type": "integer"],
            "notes": ["type": "string"],
        ],
        "required": ["meal_name", "items", "confidence", "health_score", "notes"],
        "additionalProperties": false,
    ]

    func analyzePhoto(_ image: UIImage, hint: String = "") async throws -> AnalyzedMeal {
        var text = "Estimate the nutrition of the meal in this photo."
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            text += " The user adds: \(hint)"
        }
        let data = try await client.structured(system: Self.system, content: .init(text: text, image: image), schema: Self.mealSchema)
        return try Self.parse(data, source: .photo)
    }

    func analyzeLabel(_ image: UIImage) async throws -> AnalyzedMeal {
        let text = """
        This is a photo of a packaged food's nutrition facts label, and possibly its name. Read the label. \
        Produce exactly one item whose unit is "serving", quantity 1, grams_per_unit equal to the stated serving size in grams \
        (estimate if only volume is given), and the per-serving nutrients exactly as printed. Name the product if visible.
        """
        let data = try await client.structured(system: Self.system, content: .init(text: text, image: image), schema: Self.mealSchema)
        return try Self.parse(data, source: .label)
    }

    func analyzeDescription(_ description: String) async throws -> AnalyzedMeal {
        let text = "Estimate the nutrition of this meal from the user's description: \(description)"
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
        let data = try await client.structured(system: Self.system, content: .init(text: text, image: image), schema: Self.mealSchema)
        var result = try Self.parse(data, source: previous.source)
        result.source = previous.source
        return result
    }

    static func parse(_ data: Data, source: MealSource) throws -> AnalyzedMeal {
        struct Raw: Decodable {
            struct Item: Decodable {
                var name: String
                var quantity: Double
                var unit: String
                var grams_per_unit: Double
                var calories_per_unit: Double
                var protein_g_per_unit: Double
                var carbs_g_per_unit: Double
                var fat_g_per_unit: Double
                var fiber_g_per_unit: Double
                var sugar_g_per_unit: Double
                var sodium_mg_per_unit: Double
                var confidence: Double
            }
            var meal_name: String
            var items: [Item]
            var confidence: Double
            var health_score: Int
            var notes: String
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw AIError.badJSON(String(decoding: data, as: UTF8.self))
        }
        let items = raw.items.map { r in
            AnalyzedMeal.Item(
                name: r.name,
                quantity: max(r.quantity, 0),
                unit: r.unit,
                gramsPerUnit: r.grams_per_unit > 0 ? r.grams_per_unit : nil,
                base: Nutrients(calories: max(r.calories_per_unit, 0), protein: max(r.protein_g_per_unit, 0),
                                carbs: max(r.carbs_g_per_unit, 0), fat: max(r.fat_g_per_unit, 0),
                                fiber: max(r.fiber_g_per_unit, 0), sugar: max(r.sugar_g_per_unit, 0),
                                sodium: max(r.sodium_mg_per_unit, 0)),
                confidence: min(max(r.confidence, 0), 1))
        }
        return AnalyzedMeal(name: raw.meal_name, items: items, notes: raw.notes,
                            healthScore: min(max(raw.health_score, 1), 10),
                            confidence: min(max(raw.confidence, 0), 1), source: source)
    }

    static func trim(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.2g", v)
    }
}
