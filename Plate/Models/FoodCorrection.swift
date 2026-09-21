import Foundation
import SwiftData

/// What this person's portions actually look like, learned from the times they fixed an estimate.
///
/// The model knows what a chicken breast is. What it cannot know is that yours is 220 g rather than
/// the 120 g reference serving, and it has no way to find out except by being told. Every time an
/// estimate is corrected before saving, the difference is recorded here, and future scans of the same
/// food are given the portion this person actually eats.
///
/// This only ever learns from an explicit correction. It does not learn from a goal, a target, or a
/// number the app itself suggested, because a system that adjusts estimates toward what someone wants
/// to see stops being a measurement. It learns from the one thing the user knows better than the
/// model: what was on their own plate.
@Model
final class FoodCorrection {
    /// Lower cased and stripped, so "Chicken Breast" and "chicken breast " are the same food.
    var key: String = ""
    var displayName: String = ""
    /// The portion the user settled on, in grams, when grams were known.
    var grams: Double?
    /// Their portion divided by the model's, kept for foods with no gram figure.
    var ratio: Double = 1
    var calories: Double = 0
    var count: Int = 0
    var updatedAt: Date = Date()

    init(key: String, displayName: String, grams: Double?, ratio: Double, calories: Double) {
        self.key = key
        self.displayName = displayName
        self.grams = grams
        self.ratio = ratio
        self.calories = calories
        self.count = 1
        self.updatedAt = Date()
    }

    static func normalize(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// A correction worth recording.
    ///
    /// Rounding a portion from 1 to 1.1 is noise, and so is a change the app itself offered. The
    /// threshold is deliberately coarse: this should fire when someone says "that was nearly double",
    /// not every time they nudge a slider.
    static let threshold = 0.2
    static let plausibleRange = 0.2...5.0

    static func isWorthLearning(estimated: Double, corrected: Double) -> Bool {
        guard estimated > 0, corrected > 0 else { return false }
        let ratio = corrected / estimated
        guard plausibleRange.contains(ratio) else { return false }
        return abs(ratio - 1) >= threshold
    }

    /// Later corrections count for more than older ones, but one odd day should not erase a habit.
    /// A simple running average over the last few corrections, weighted toward the newest.
    func absorb(grams newGrams: Double?, ratio newRatio: Double, calories newCalories: Double) {
        let weight = 0.6
        if let newGrams, newGrams > 0 {
            grams = grams.map { $0 * (1 - weight) + newGrams * weight } ?? newGrams
        }
        ratio = ratio * (1 - weight) + newRatio * weight
        calories = calories * (1 - weight) + newCalories * weight
        count += 1
        updatedAt = Date()
    }

    /// How it is described to the model. Grams when they are known, because a weight is unambiguous
    /// in a way that "1.8 times" is not.
    var promptPhrase: String {
        if let grams, grams > 0 {
            return "\(displayName) is usually about \(Int(grams.rounded())) g for them"
        }
        let times = (ratio * 10).rounded() / 10
        return "\(displayName) is usually about \(times) times a reference serving for them"
    }
}
