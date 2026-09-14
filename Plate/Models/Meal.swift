import Foundation
import SwiftData

enum MealSource: String, Codable {
    case photo, label, barcode, describe, saved, search, manual
    var symbol: String {
        switch self {
        case .photo: return "camera.fill"
        case .label: return "doc.text.viewfinder"
        case .barcode: return "barcode.viewfinder"
        case .describe: return "text.bubble.fill"
        case .saved: return "bookmark.fill"
        case .search: return "magnifyingglass"
        case .manual: return "pencil"
        }
    }
}

/// Nutrients for one serving or one logged amount. Grams unless noted; sodium in milligrams.
struct Nutrients: Codable, Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0

    static let zero = Nutrients()

    static func + (a: Nutrients, b: Nutrients) -> Nutrients {
        Nutrients(calories: a.calories + b.calories, protein: a.protein + b.protein,
                  carbs: a.carbs + b.carbs, fat: a.fat + b.fat, fiber: a.fiber + b.fiber,
                  sugar: a.sugar + b.sugar, sodium: a.sodium + b.sodium)
    }

    static func * (a: Nutrients, k: Double) -> Nutrients {
        Nutrients(calories: a.calories * k, protein: a.protein * k, carbs: a.carbs * k,
                  fat: a.fat * k, fiber: a.fiber * k, sugar: a.sugar * k, sodium: a.sodium * k)
    }
}

@Model
final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var name: String = ""
    var sourceRaw: String = MealSource.manual.rawValue
    var notes: String = ""
    var healthScore: Int? = nil
    var confidence: Double? = nil
    @Attribute(.externalStorage) var imageData: Data? = nil

    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal)
    var items: [MealItem] = []

    init(name: String, date: Date = Date(), source: MealSource) {
        self.name = name
        self.date = date
        self.sourceRaw = source.rawValue
    }

    var source: MealSource {
        get { MealSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var totals: Nutrients {
        get { Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar, sodium: sodium) }
        set {
            calories = newValue.calories; protein = newValue.protein; carbs = newValue.carbs
            fat = newValue.fat; fiber = newValue.fiber; sugar = newValue.sugar; sodium = newValue.sodium
        }
    }

    /// Totals are always derived from the items so editing a portion updates every number.
    func recalculate() {
        totals = items.reduce(Nutrients.zero) { $0 + $1.scaled }
    }
}

@Model
final class MealItem {
    var id: UUID = UUID()
    var name: String = ""
    /// How many of `unit` the user ate. Per-unit nutrients are stored in `base`.
    var quantity: Double = 1
    var unit: String = "serving"
    var gramsPerUnit: Double? = nil
    var confidence: Double? = nil
    var order: Int = 0

    var baseCalories: Double = 0
    var baseProtein: Double = 0
    var baseCarbs: Double = 0
    var baseFat: Double = 0
    var baseFiber: Double = 0
    var baseSugar: Double = 0
    var baseSodium: Double = 0

    var meal: MealEntry? = nil

    init(name: String, quantity: Double, unit: String, gramsPerUnit: Double?, base: Nutrients, confidence: Double? = nil, order: Int = 0) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.gramsPerUnit = gramsPerUnit
        self.confidence = confidence
        self.order = order
        self.base = base
    }

    var base: Nutrients {
        get { Nutrients(calories: baseCalories, protein: baseProtein, carbs: baseCarbs, fat: baseFat, fiber: baseFiber, sugar: baseSugar, sodium: baseSodium) }
        set {
            baseCalories = newValue.calories; baseProtein = newValue.protein; baseCarbs = newValue.carbs
            baseFat = newValue.fat; baseFiber = newValue.fiber; baseSugar = newValue.sugar; baseSodium = newValue.sodium
        }
    }

    var scaled: Nutrients { base * quantity }

    var grams: Double? { gramsPerUnit.map { $0 * quantity } }
}

@Model
final class SavedFood {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var barcode: String? = nil
    var servingLabel: String = "serving"
    var servingGrams: Double? = nil
    var lastUsed: Date = Date()
    var useCount: Int = 0

    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0

    init(name: String, brand: String = "", barcode: String? = nil, servingLabel: String, servingGrams: Double?, perServing: Nutrients) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.perServing = perServing
    }

    var perServing: Nutrients {
        get { Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar, sodium: sodium) }
        set {
            calories = newValue.calories; protein = newValue.protein; carbs = newValue.carbs
            fat = newValue.fat; fiber = newValue.fiber; sugar = newValue.sugar; sodium = newValue.sodium
        }
    }
}

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0
    var fromHealth: Bool = false

    init(date: Date = Date(), weightKg: Double, fromHealth: Bool = false) {
        self.date = date
        self.weightKg = weightKg
        self.fromHealth = fromHealth
    }
}
