import Foundation

/// Pure helpers over the meal log: per-day totals, streaks, rollover.
enum DayStats {
    static func sameDay(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, inSameDayAs: b) }

    /// What one particular day's calorie allowance actually is.
    ///
    /// The stored target is a baseline. A given day can differ from it for three reasons, and Today
    /// has always shown the adjusted figure. This used to live inside the Today screen, which meant
    /// anything else that quoted a target quoted the baseline instead and disagreed with the ring by
    /// however much had rolled over. One function now, so they cannot drift apart again.
    struct DayTarget: Equatable {
        var base: Int
        var cycling: Int       // signed, from calorie cycling
        var rollover: Int      // yesterday's unspent calories, capped
        var earned: Int        // movement beyond what the plan already assumed
        var total: Int

        /// The parts that moved today off the baseline, ready to be read aloud.
        var adjustments: [(label: String, amount: Int)] {
            [("calorie cycling", cycling), ("rolled over", rollover), ("earned by moving", earned)]
                .filter { $0.1 != 0 }
        }
    }

    static func dayTarget(profile: Profile, meals: [MealEntry], day: Date,
                          extraBurn: Int = 0) -> DayTarget {
        let base = profile.calorieTarget
        var cycled = base
        if let split = NutritionMath.daySplit(calories: base, cycling: profile.cycling,
                                              trainingDaysPerWeek: profile.trainingDaysPerWeek),
           profile.cycling == .weekends {
            let weekday = Calendar.current.component(.weekday, from: day)
            cycled = (weekday == 1 || weekday == 7) ? split.higher : split.lower
        }
        // Rollover is worked out against whichever day is being looked at, so it stays meaningful
        // when scrolling back. Movement does not: it is only ever measured for today.
        let rollover = profile.rolloverCalories
            ? DayStats.rollover(target: base, meals: meals, today: day) : 0
        let earned = (profile.addExerciseCalories && Calendar.current.isDateInToday(day)) ? extraBurn : 0
        return DayTarget(base: base,
                         cycling: cycled - base,
                         rollover: rollover,
                         earned: earned,
                         total: cycled + rollover + earned)
    }

    static func totals(on day: Date, meals: [MealEntry]) -> Nutrients {
        meals.filter { sameDay($0.date, day) }.reduce(Nutrients.zero) { $0 + $1.totals }
    }

    /// Consecutive days with at least one entry, counting back from today (or yesterday if today is empty).
    static func streak(meals: [MealEntry], today: Date = Date()) -> Int {
        let cal = Calendar.current
        let days = Set(meals.map { cal.startOfDay(for: $0.date) })
        var cursor = cal.startOfDay(for: today)
        if !days.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
            if !days.contains(cursor) { return 0 }
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    /// Unused calories from yesterday that carry into today, capped so a skipped day is not a feast.
    static func rollover(target: Int, meals: [MealEntry], today: Date = Date(), cap: Int = 250) -> Int {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let eaten = totals(on: yesterday, meals: meals).calories
        guard eaten > 0 else { return 0 }
        return min(cap, max(0, target - Int(eaten)))
    }

    /// Daily calorie totals for the last `days` days, oldest first. Days with nothing logged are nil.
    static func dailyCalories(meals: [MealEntry], days: Int, endingOn end: Date = Date()) -> [(Date, Double?)] {
        let cal = Calendar.current
        let endDay = cal.startOfDay(for: end)
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: endDay)!
            let t = totals(on: day, meals: meals)
            return (day, t.calories > 0 ? t.calories : nil)
        }
    }
}
