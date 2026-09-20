import Foundation

/// Body fat, lean mass, and the numbers that describe a body better than weight alone.
///
/// The tape measure method here is the one the US Navy uses. It lands within about three to four
/// points of a DEXA scan, which is not good enough to quote as a fact but is plenty to watch a
/// trend, and it costs nothing. Every formula is cited in the Sources screen.
enum BodyComposition {

    // MARK: Body fat

    enum Source: String, Codable, CaseIterable, Identifiable {
        case tape, entered, estimated
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tape: return "Tape measure"
            case .entered: return "Entered by you"
            case .estimated: return "Estimated from BMI"
            }
        }
        var confidence: String {
            switch self {
            case .tape: return "Within about 3 to 4 points of a DEXA scan."
            case .entered: return "As accurate as wherever you got it."
            case .estimated: return "Rough. A tape measure is much better."
            }
        }
    }

    struct Estimate: Equatable {
        var percent: Double
        var source: Source
    }

    /// US Navy circumference method (Hodgdon and Beckett, 1984). Centimeters in, percent out.
    /// Returns nil when a measurement is missing or the numbers cannot give a sensible answer.
    static func navyBodyFat(sex: Sex, heightCm: Double, neckCm: Double, waistCm: Double, hipCm: Double?) -> Double? {
        guard heightCm >= 120, neckCm >= 20, waistCm >= 40 else { return nil }
        let percent: Double
        switch sex {
        case .male:
            let girth = waistCm - neckCm
            guard girth > 1 else { return nil }
            percent = 495 / (1.0324 - 0.19077 * log10(girth) + 0.15456 * log10(heightCm)) - 450
        case .female:
            guard let hipCm, hipCm >= 40 else { return nil }
            let girth = waistCm + hipCm - neckCm
            guard girth > 1 else { return nil }
            percent = 495 / (1.29579 - 0.35004 * log10(girth) + 0.22100 * log10(heightCm)) - 450
        }
        guard percent.isFinite, percent > 2, percent < 70 else { return nil }
        return percent
    }

    /// Deurenberg (1991), from BMI, age and sex. The last resort when there is no tape measure.
    /// It cannot tell a muscular body from a heavy one, so it reads high on lifters.
    static func bmiBodyFat(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double? {
        let bmi = self.bmi(weightKg: weightKg, heightCm: heightCm)
        guard bmi > 10, bmi < 60 else { return nil }
        let percent = 1.20 * bmi + 0.23 * Double(age) - 10.8 * (sex == .male ? 1 : 0) - 5.4
        guard percent.isFinite, percent > 2, percent < 70 else { return nil }
        return percent
    }

    /// The best body fat number available: what the user entered, then the tape, then BMI.
    static func bestEstimate(sex: Sex, age: Int, heightCm: Double, weightKg: Double,
                             entered: Double?, neckCm: Double?, waistCm: Double?, hipCm: Double?) -> Estimate? {
        if let entered, entered > 2, entered < 70 { return Estimate(percent: entered, source: .entered) }
        if let neckCm, let waistCm,
           let tape = navyBodyFat(sex: sex, heightCm: heightCm, neckCm: neckCm, waistCm: waistCm, hipCm: hipCm) {
            return Estimate(percent: tape, source: .tape)
        }
        if let rough = bmiBodyFat(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg) {
            return Estimate(percent: rough, source: .estimated)
        }
        return nil
    }

    // MARK: Lean mass and the indexes built on it

    static func leanMassKg(weightKg: Double, bodyFatPercent: Double) -> Double {
        weightKg * (1 - bodyFatPercent / 100)
    }

    static func fatMassKg(weightKg: Double, bodyFatPercent: Double) -> Double {
        weightKg * bodyFatPercent / 100
    }

    /// Fat free mass index: lean mass for your height. Unlike BMI it does not call a lifter obese.
    static func ffmi(leanMassKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        guard m > 0.5 else { return 0 }
        return leanMassKg / (m * m)
    }

    /// FFMI adjusted to a 1.8 m frame so tall and short people can be compared (Kouri, 1995).
    static func normalizedFFMI(leanMassKg: Double, heightCm: Double) -> Double {
        ffmi(leanMassKg: leanMassKg, heightCm: heightCm) + 6.1 * (1.8 - heightCm / 100)
    }

    /// Where a normalized FFMI sits. The drug free ceiling is around 25 for men and 22 for women,
    /// which is why anything above that is described rather than praised.
    static func ffmiLabel(_ value: Double, sex: Sex) -> String {
        let marks: [(Double, String)] = sex == .male
            ? [(17, "Below average"), (19, "Average"), (21, "Above average"), (23, "Strong"), (25, "Very muscular")]
            : [(14, "Below average"), (16, "Average"), (17.5, "Above average"), (19, "Strong"), (21.5, "Very muscular")]
        for (limit, label) in marks where value < limit { return label }
        return "Exceptional"
    }

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        guard m > 0.5 else { return 0 }
        return weightKg / (m * m)
    }

    /// CDC adult categories. BMI describes a population, not a person, so the app never uses it alone.
    static func bmiLabel(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case ..<25: return "Healthy"
        case ..<30: return "Overweight"
        default: return "Obese"
        }
    }

    /// Waist divided by height. Keeping it under 0.5 is the simplest evidence backed health target
    /// there is, and it works across heights and sexes.
    static func waistToHeight(waistCm: Double, heightCm: Double) -> Double? {
        guard heightCm > 0, waistCm > 0 else { return nil }
        return waistCm / heightCm
    }

    static func waistToHeightLabel(_ ratio: Double) -> String {
        switch ratio {
        case ..<0.4: return "Low, check with a doctor if you are losing weight quickly"
        case ..<0.5: return "Healthy"
        case ..<0.6: return "Increased health risk"
        default: return "High health risk"
        }
    }

    // MARK: Categories and healthy ranges

    struct Band: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var range: ClosedRange<Double>
        var detail: String
    }

    /// American Council on Exercise body fat categories.
    static func bands(for sex: Sex) -> [Band] {
        sex == .male
            ? [Band(name: "Essential", range: 2...5, detail: "The minimum the body needs. Not a place to live."),
               Band(name: "Athletes", range: 6...13, detail: "Visible abs, high training demand."),
               Band(name: "Fitness", range: 14...17, detail: "Lean and sustainable."),
               Band(name: "Average", range: 18...24, detail: "Typical for an adult man."),
               Band(name: "Above average", range: 25...60, detail: "Losing fat here improves most health markers.")]
            : [Band(name: "Essential", range: 10...13, detail: "The minimum the body needs. Not a place to live."),
               Band(name: "Athletes", range: 14...20, detail: "High training demand. Watch your cycle and energy."),
               Band(name: "Fitness", range: 21...24, detail: "Lean and sustainable."),
               Band(name: "Average", range: 25...31, detail: "Typical for an adult woman."),
               Band(name: "Above average", range: 32...65, detail: "Losing fat here improves most health markers.")]
    }

    /// The published categories leave small gaps between bands, so a number like 17.9 percent falls
    /// through `contains`. Anything in a gap belongs to the band below it, never to the last one.
    static func band(for percent: Double, sex: Sex) -> Band? {
        let list = bands(for: sex)
        if let exact = list.first(where: { $0.range.contains(percent) }) { return exact }
        return list.last(where: { percent >= $0.range.lowerBound }) ?? list.first
    }

    /// The lowest body fat worth aiming for. Below this, hormones, mood, and sleep usually suffer.
    static func healthyFloor(for sex: Sex) -> Double { sex == .male ? 8 : 16 }

    /// Weight range that puts BMI between 18.5 and 24.9. A starting point, not a verdict.
    static func healthyWeightRange(heightCm: Double) -> ClosedRange<Double> {
        let m = heightCm / 100
        return (18.5 * m * m)...(24.9 * m * m)
    }

    /// What you would weigh at a target body fat if you kept every gram of lean mass. This is the
    /// honest version of a goal weight: it comes from composition rather than a number you liked.
    static func weightAtBodyFat(currentWeightKg: Double, currentBodyFat: Double, targetBodyFat: Double) -> Double? {
        guard currentBodyFat > 0, currentBodyFat < 70, targetBodyFat > 0, targetBodyFat < 70 else { return nil }
        let lean = leanMassKg(weightKg: currentWeightKg, bodyFatPercent: currentBodyFat)
        return lean / (1 - targetBodyFat / 100)
    }
}
