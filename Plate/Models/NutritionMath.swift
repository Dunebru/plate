import Foundation

/// Calorie and macro math. Mifflin-St Jeor for resting energy, standard activity multipliers,
/// 7,700 kcal per kilogram of body weight for the weekly pace.
enum NutritionMath {
    struct Inputs {
        var sex: Sex
        var age: Int
        var heightCm: Double
        var weightKg: Double
        var activity: ActivityLevel
        var goal: Goal
        var paceKgPerWeek: Double
    }

    struct Plan: Equatable {
        var bmr: Int
        var tdee: Int
        var calories: Int
        var protein: Int
        var carbs: Int
        var fat: Int
    }

    static let kcalPerKg = 7700.0

    static func bmr(_ i: Inputs) -> Double {
        let base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * Double(i.age)
        return i.sex == .male ? base + 5 : base - 161
    }

    static func tdee(_ i: Inputs) -> Double {
        bmr(i) * i.activity.multiplier
    }

    static func plan(for i: Inputs) -> Plan {
        let rest = bmr(i)
        let maintenance = tdee(i)
        let dailyDelta = i.paceKgPerWeek * kcalPerKg / 7
        var calories: Double
        switch i.goal {
        case .lose: calories = maintenance - dailyDelta
        case .maintain: calories = maintenance
        case .gain: calories = maintenance + dailyDelta
        }
        let floor = i.sex == .male ? 1500.0 : 1200.0
        calories = max(calories, floor)

        // Protein per kilogram: higher in a deficit to protect muscle.
        let proteinPerKg: Double
        switch i.goal {
        case .lose: proteinPerKg = 1.8
        case .maintain: proteinPerKg = 1.6
        case .gain: proteinPerKg = 1.8
        }
        var protein = proteinPerKg * i.weightKg
        protein = min(protein, calories * 0.40 / 4)
        var fat = calories * 0.28 / 9
        fat = max(fat, 0.6 * i.weightKg)
        var carbs = (calories - protein * 4 - fat * 9) / 4
        if carbs < 50 {
            carbs = 50
            fat = max((calories - protein * 4 - carbs * 4) / 9, 30)
        }
        return Plan(bmr: Int(rest.rounded()), tdee: Int(maintenance.rounded()),
                    calories: Int((calories / 10).rounded() * 10),
                    protein: Int(protein.rounded()), carbs: Int(carbs.rounded()), fat: Int(fat.rounded()))
    }

    /// Weeks until the target weight at the chosen pace.
    static func weeksToGoal(_ i: Inputs, targetKg: Double) -> Double? {
        guard i.goal != .maintain, i.paceKgPerWeek > 0 else { return nil }
        let distance = abs(targetKg - i.weightKg)
        return distance / i.paceKgPerWeek
    }

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        return weightKg / (m * m)
    }

    static func bmiLabel(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case ..<25: return "Healthy"
        case ..<30: return "Overweight"
        default: return "Obese"
        }
    }

    /// Reality check: what the scale says your maintenance actually is, from logged intake and weight trend.
    struct RealityCheck: Equatable {
        var days: Int
        var averageIntake: Int
        var weightChangeKg: Double
        var impliedTDEE: Int
        var suggestedCalories: Int
    }

    static func realityCheck(intakeByDay: [Double], startWeightKg: Double, endWeightKg: Double, days: Int, goal: Goal, paceKgPerWeek: Double) -> RealityCheck? {
        guard days >= 14, intakeByDay.count >= 10 else { return nil }
        let avg = intakeByDay.reduce(0, +) / Double(intakeByDay.count)
        let change = endWeightKg - startWeightKg
        let implied = avg - change * kcalPerKg / Double(days)
        let dailyDelta = paceKgPerWeek * kcalPerKg / 7
        let suggested: Double
        switch goal {
        case .lose: suggested = implied - dailyDelta
        case .maintain: suggested = implied
        case .gain: suggested = implied + dailyDelta
        }
        return RealityCheck(days: days, averageIntake: Int(avg.rounded()), weightChangeKg: change,
                            impliedTDEE: Int(implied.rounded()), suggestedCalories: Int((suggested / 10).rounded() * 10))
    }
}

enum Units {
    static func kgToLb(_ kg: Double) -> Double { kg * 2.2046226218 }
    static func lbToKg(_ lb: Double) -> Double { lb / 2.2046226218 }
    static func cmToFeetInches(_ cm: Double) -> (Int, Int) {
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int((totalInches - Double(feet) * 12).rounded())
        return inches == 12 ? (feet + 1, 0) : (feet, inches)
    }
    static func feetInchesToCm(_ feet: Int, _ inches: Int) -> Double {
        (Double(feet) * 12 + Double(inches)) * 2.54
    }

    static func weightString(_ kg: Double, _ units: UnitSystem, decimals: Int = 1) -> String {
        switch units {
        case .metric: return String(format: "%.\(decimals)f kg", kg)
        case .imperial: return String(format: "%.\(decimals)f lb", kgToLb(kg))
        }
    }

    static func heightString(_ cm: Double, _ units: UnitSystem) -> String {
        switch units {
        case .metric: return "\(Int(cm.rounded())) cm"
        case .imperial:
            let (f, i) = cmToFeetInches(cm)
            return "\(f)'\(i)\""
        }
    }
}
