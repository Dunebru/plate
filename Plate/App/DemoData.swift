#if DEBUG
import Foundation
import SwiftData

/// Fills the store with a realistic few weeks so every screen can be looked at without spending a
/// month logging. Debug builds only, and only when the app is launched with --demo-profile.
enum DemoData {
    static var requested: Bool { CommandLine.arguments.contains("--demo-profile") }

    static func seed(into context: ModelContext) {
        try? context.delete(model: MealEntry.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: BodyMeasurement.self)
        try? context.delete(model: Profile.self)

        let profile = Profile()
        profile.sex = .male
        profile.birthDate = Calendar.current.date(byAdding: .year, value: -27, to: Date())
        profile.birthYear = Calendar.current.component(.year, from: profile.birthDate ?? Date())
        profile.heightCm = 180
        profile.weightKg = 84.2
        profile.neckCm = 39
        profile.waistCm = 89
        profile.dailyActivity = .desk
        profile.trainingStyle = .strength
        profile.trainingDaysPerWeek = 4
        profile.trainingMinutes = 60
        profile.experience = .intermediate
        profile.goal = .lose
        profile.targetWeightKg = 77
        profile.paceKgPerWeek = 0.5
        profile.targetBodyFat = 14
        profile.diet = .highProtein
        profile.mealPattern = .threePlusSnacks
        profile.cycling = .trainingDays
        profile.focusAreas = [.midsection, .chest, .arms]
        profile.areaGoal = .both
        profile.obstacles = [.lateNight, .socialEating]
        profile.avoids = ["shellfish"]
        profile.drinksPerWeek = 3
        profile.writeToHealth = false   // no permission prompts while looking at screens
        profile.onboarded = true
        profile.recalculateTargets()
        // --legacy-profile reproduces someone who finished the older, shorter setup, so the offer
        // to answer the newer questions can be looked at.
        if CommandLine.arguments.contains("--legacy-profile") {
            profile.dailyActivityRaw = nil
            profile.activity = .light
            profile.trainingStyle = .none
            profile.trainingDaysPerWeek = 0
        }
        context.insert(profile)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Six weeks of weigh ins, trending down with the usual daily noise.
        for day in stride(from: 41, through: 0, by: -1) {
            guard day % 7 != 3 else { continue }        // a few missed days, like real life
            let date = cal.date(byAdding: .day, value: -day, to: today)!
            let trend = 87.0 - Double(41 - day) * 0.068
            let noise = [0.0, 0.5, -0.3, 0.8, -0.2, 0.35, -0.55][day % 7]
            context.insert(WeightEntry(date: cal.date(byAdding: .hour, value: 7, to: date)!,
                                       weightKg: (trend + noise * 0.9).rounded(toPlaces: 1)))
        }

        // Tape measurements every fortnight.
        for (index, weeksAgo) in [6, 4, 2, 0].enumerated() {
            let m = BodyMeasurement(date: cal.date(byAdding: .day, value: -weeksAgo * 7, to: today)!)
            m.waistCm = 93 - Double(index) * 1.3
            m.chestCm = 103 - Double(index) * 0.3
            m.neckCm = 39.5 - Double(index) * 0.15
            m.armCm = 35.5 + Double(index) * 0.1
            m.thighCm = 58 - Double(index) * 0.4
            m.weightKg = 87 - Double(index) * 0.95
            m.refreshBodyFat(sex: .male, heightCm: 180, fallbackWeightKg: m.weightKg ?? 84)
            context.insert(m)
        }

        // Four weeks of meals, roughly on target with the odd big day.
        let menu: [(String, MealSource, Nutrients)] = [
            ("Greek yogurt, berries and granola", .describe, Nutrients(calories: 420, protein: 32, carbs: 48, fat: 11, fiber: 6, sugar: 22, sodium: 140)),
            ("Chicken, rice and broccoli", .photo, Nutrients(calories: 640, protein: 52, carbs: 68, fat: 14, fiber: 7, sugar: 4, sodium: 520)),
            ("Protein shake and banana", .saved, Nutrients(calories: 280, protein: 28, carbs: 34, fat: 3, fiber: 3, sugar: 20, sodium: 95)),
            ("Salmon, potatoes and salad", .photo, Nutrients(calories: 710, protein: 46, carbs: 54, fat: 32, fiber: 8, sugar: 6, sodium: 480)),
            ("Eggs on sourdough", .describe, Nutrients(calories: 480, protein: 26, carbs: 38, fat: 24, fiber: 4, sugar: 3, sodium: 620)),
            ("Burrito bowl", .photo, Nutrients(calories: 820, protein: 44, carbs: 86, fat: 32, fiber: 12, sugar: 8, sodium: 1340)),
            ("Cottage cheese and crackers", .barcode, Nutrients(calories: 260, protein: 24, carbs: 22, fat: 8, fiber: 1, sugar: 5, sodium: 540)),
        ]
        for day in stride(from: 27, through: 0, by: -1) {
            guard day % 9 != 5 else { continue }        // a couple of unlogged days
            let date = cal.date(byAdding: .day, value: -day, to: today)!
            let count = day % 6 == 0 ? 4 : 3
            for slot in 0..<count {
                let (name, source, nutrients) = menu[(day * 3 + slot) % menu.count]
                let meal = MealEntry(name: name,
                                     date: cal.date(byAdding: .hour, value: 8 + slot * 4, to: date)!,
                                     source: source)
                meal.items = [MealItem(name: name, quantity: 1, unit: "serving", gramsPerUnit: nil, base: nutrients, confidence: 0.75)]
                meal.healthScore = 6 + (slot % 3)
                meal.recalculate()
                context.insert(meal)
            }
        }
        try? context.save()
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
#endif
