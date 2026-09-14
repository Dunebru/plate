import Foundation
import SwiftData

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Very active"
        case .veryActive: return "Athlete"
        }
    }
    var detail: String {
        switch self {
        case .sedentary: return "Desk job, little exercise"
        case .light: return "Exercise 1 to 3 days a week"
        case .moderate: return "Exercise 3 to 5 days a week"
        case .active: return "Exercise 6 to 7 days a week"
        case .veryActive: return "Hard training twice a day or a physical job"
        }
    }
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lose: return "Lose weight"
        case .maintain: return "Maintain"
        case .gain: return "Gain weight"
        }
    }
    var symbol: String {
        switch self {
        case .lose: return "arrow.down.right"
        case .maintain: return "equal"
        case .gain: return "arrow.up.right"
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String { self == .metric ? "Metric" : "Imperial" }
}

@Model
final class Profile {
    var createdAt: Date = Date()
    var sexRaw: String = Sex.male.rawValue
    var birthYear: Int = 1995
    var heightCm: Double = 175
    var weightKg: Double = 75
    var activityRaw: String = ActivityLevel.light.rawValue
    var goalRaw: String = Goal.maintain.rawValue
    var targetWeightKg: Double = 75
    /// Positive number of kilograms per week the user wants to lose or gain.
    var paceKgPerWeek: Double = 0.5
    var unitsRaw: String = UnitSystem.metric.rawValue

    var calorieTarget: Int = 2000
    var proteinTarget: Int = 150
    var carbTarget: Int = 200
    var fatTarget: Int = 65

    var addExerciseCalories: Bool = false
    var rolloverCalories: Bool = false
    var writeToHealth: Bool = true
    var onboarded: Bool = false

    init() {}

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }
    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .light }
        set { activityRaw = newValue.rawValue }
    }
    var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }
    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }
    var age: Int {
        max(13, Calendar.current.component(.year, from: Date()) - birthYear)
    }

    var inputs: NutritionMath.Inputs {
        .init(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
              activity: activity, goal: goal, paceKgPerWeek: paceKgPerWeek)
    }

    /// Recomputes calorie and macro targets from the current body stats and goal.
    func recalculateTargets() {
        let plan = NutritionMath.plan(for: inputs)
        calorieTarget = plan.calories
        proteinTarget = plan.protein
        carbTarget = plan.carbs
        fatTarget = plan.fat
    }
}
