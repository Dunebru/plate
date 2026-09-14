import Foundation

/// Pure helpers over the meal log: per-day totals, streaks, rollover.
enum DayStats {
    static func sameDay(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, inSameDayAs: b) }

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
