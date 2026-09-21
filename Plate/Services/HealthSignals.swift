import Foundation
import HealthKit

/// What a wearable can tell Plate, and what it cannot.
///
/// A Whoop, an Apple Watch and the phone in your pocket all write into Apple Health, so a burn
/// read out of Health is somebody's model of you rather than a measurement of you. It is still
/// better evidence than an equation fitted to a study population, because it moves when you move.
/// Everything here is built to fail closed. A day the band spent on the nightstand, two devices
/// writing the same hours, or a source that reports a whole day where Plate expects only the
/// movement on top of it all end the same way: the number is refused and the prediction stands.
///
/// The queries live in `HealthStore`. This file is the arithmetic, kept separate so it can be
/// tested without a device, a watch, or anybody's permission.
enum HealthSignals {

    /// Turning the feature on is a choice about this phone rather than about the plan, so it is
    /// stored here rather than on the profile.
    static let defaultsKey = "health.readWearable"

    // MARK: Who wrote it

    /// Health hands back a bundle identifier and a hardware model. This turns those into
    /// something worth putting on screen, and into an order of preference.
    enum Source: Equatable, Hashable {
        case whoop
        case appleWatch
        case iPhone
        case other(String)

        var label: String {
            switch self {
            case .whoop: return "Whoop"
            case .appleWatch: return "Apple Watch"
            case .iPhone: return "iPhone"
            case .other(let name): return name
            }
        }

        /// Which source to believe when several are writing the same hours. Health does not
        /// deduplicate a plain sum across sources, so exactly one of them gets used and the rest
        /// are ignored. A band worn through the night beats a watch taken off to charge, and both
        /// beat a phone, which only knows the walking it happened to be carried for.
        var rank: Int {
            switch self {
            case .whoop: return 0
            case .appleWatch: return 1
            case .other: return 2
            case .iPhone: return 3
            }
        }
    }

    /// Apple writes its own samples under a per device bundle identifier, so the hardware model is
    /// the only thing that separates a watch from a phone. Third party apps are named by their own
    /// identifier instead.
    static func classify(bundleIdentifier: String, productType: String?, name: String) -> Source {
        let bundle = bundleIdentifier.lowercased()
        if bundle.hasPrefix("com.whoop") || name.range(of: "whoop", options: .caseInsensitive) != nil {
            return .whoop
        }
        if let productType {
            if productType.hasPrefix("Watch") { return .appleWatch }
            if productType.hasPrefix("iPhone") { return .iPhone }
        }
        return .other(name.isEmpty ? bundleIdentifier : name)
    }

    // MARK: Burn

    struct DayEnergy: Equatable {
        var date: Date
        /// Movement on top of simply being alive.
        var activeKcal: Double
        /// Being alive. Nil when nothing in Health writes it, which is the normal case without a
        /// watch.
        var basalKcal: Double?
    }

    /// What the equation currently believes. Any measurement has to be judged against this, and
    /// any part of the day the measurement does not cover has to be filled from it.
    struct Prediction: Equatable {
        var bmr: Double
        var tdee: Double
        var trainingKcalPerDay: Double

        init(bmr: Double, tdee: Double, trainingKcalPerDay: Double) {
            self.bmr = bmr
            self.tdee = tdee
            self.trainingKcalPerDay = trainingKcalPerDay
        }

        init(_ inputs: NutritionMath.Inputs) {
            self.init(bmr: NutritionMath.bmr(inputs),
                      tdee: NutritionMath.tdee(inputs),
                      trainingKcalPerDay: NutritionMath.trainingKcalPerDay(inputs))
        }

        /// The day with training taken out. Plate already counts everyday movement and training
        /// separately so that neither is doubled, so this is the half a session based measurement
        /// can be laid on top of without counting anything twice.
        var restAndEverydayKcal: Double { max(0, tdee - trainingKcalPerDay) }
    }

    enum BurnBasis: Equatable {
        /// Every hour of the day came off the device: movement and resting burn both measured.
        case wholeDay
        /// The device writes sessions and nothing between them, which is what a Whoop puts into
        /// Health. Only training is measured; resting and everyday movement stay predicted.
        case workoutsOnly
    }

    struct MeasuredBurn: Equatable {
        /// Average whole day burn.
        var tdee: Int
        /// The part Health measured: whole day movement, or session energy.
        var activeKcal: Int
        /// The part left over: a measured resting burn, or the predicted rest of the day.
        var restingKcal: Int
        var basis: BurnBasis
        /// Whole days the average is built from. Today is never one of them.
        var days: Int
        var sessions: Int
        var source: Source
        /// 0 to 1, from how much of the day and the window the device actually covered.
        var confidence: Double
        /// Pulled back toward the equation by that confidence, and held inside a sane band.
        var blended: Int

        var isTrustworthy: Bool { confidence >= 0.5 }
    }

    /// The whole day burn a wearable implies, averaged over the days it covered.
    ///
    /// There are two ways to get one and they must never be mixed. Resting energy and active
    /// energy are different halves of the same day, so when Health holds both they add up to it.
    /// A predicted resting burn and a measured resting burn are the same half twice, so they can
    /// never add, and nothing here ever adds one to the other.
    ///
    /// When Health holds no resting energy, an active energy figure on its own is ambiguous:
    /// nothing in it says whether it covers the whole day or only the workouts the device noticed,
    /// and those two readings differ by every calorie of everyday movement. Rather than guess,
    /// this falls back to the workouts, which are unambiguous, and swaps their measured energy for
    /// the MET table estimate while the equation keeps the rest of the day.
    ///
    /// Returns nil whenever the evidence is too thin or too strange to use, which on a phone with
    /// no wearable is every time.
    static func measuredBurn(days: [DayEnergy],
                             workouts: [Workout],
                             source: Source,
                             prediction: Prediction,
                             windowDays: Int = 28) -> MeasuredBurn? {
        guard prediction.bmr > 0, prediction.tdee > 0, windowDays > 0 else { return nil }
        if let whole = wholeDayBurn(days: days, source: source, prediction: prediction, windowDays: windowDays) {
            return whole
        }
        return sessionBurn(workouts: workouts, prediction: prediction, windowDays: windowDays)
    }

    private static func wholeDayBurn(days: [DayEnergy], source: Source,
                                     prediction: Prediction, windowDays: Int) -> MeasuredBurn? {
        // Resting energy is the giveaway for whether the device was worn. It accrues whether you
        // move or not, so a day holding much less of it than the body needs is a day the device
        // spent off the wrist, and a day holding none at all is a day Health cannot describe.
        let usable = days.filter { day in
            guard let basal = day.basalKcal else { return false }
            return basal >= prediction.bmr * 0.75
        }
        guard usable.count >= 7 else { return nil }

        let count = Double(usable.count)
        let averageActive = usable.reduce(0) { $0 + $1.activeKcal } / count
        let averageResting = usable.reduce(0) { $0 + ($1.basalKcal ?? 0) } / count

        // An active figure that beats the entire resting burn, every day for a month, means the
        // source is writing a whole day total under a name that holds only the movement on top of
        // one. Adding a resting burn to that counts resting twice and inflates the target every
        // day, so the reading is refused rather than repaired.
        guard averageActive < prediction.bmr else { return nil }

        let total = averageActive + averageResting
        // Nobody sustains a day below their resting burn, and a month spent above two and a half
        // times it belongs to about a dozen people alive. Either end means two devices are writing
        // the same hours or one of them is writing nonsense.
        guard total >= prediction.bmr * 1.05, total <= prediction.bmr * 2.5 else { return nil }

        let coverage = min(1, count / Double(windowDays))
        let lengthScore = min(1, count / 14)
        let confidence = max(0, min(1, coverage * 0.7 + lengthScore * 0.3))

        return MeasuredBurn(tdee: Int(total.rounded()),
                            activeKcal: Int(averageActive.rounded()),
                            restingKcal: Int(averageResting.rounded()),
                            basis: .wholeDay,
                            days: usable.count,
                            sessions: 0,
                            source: source,
                            confidence: confidence,
                            blended: blend(total, toward: prediction.tdee, confidence: confidence))
    }

    private static func sessionBurn(workouts: [Workout], prediction: Prediction,
                                    windowDays: Int) -> MeasuredBurn? {
        let sessions = workouts.filter { $0.minutes >= 10 }
        guard sessions.count >= 3 else { return nil }
        // A session logged without an energy figure is a session Plate cannot price. If most of
        // them are like that, the average would read low and quietly cut the target.
        let withEnergy = sessions.filter { $0.kcal != nil }
        guard Double(withEnergy.count) >= Double(sessions.count) * 0.67 else { return nil }

        let perDay = Double(withEnergy.reduce(0) { $0 + ($1.kcal ?? 0) }) / Double(windowDays)
        guard perDay > 0 else { return nil }

        let total = prediction.restAndEverydayKcal + perDay
        guard total >= prediction.bmr * 1.05, total <= prediction.bmr * 2.5 else { return nil }

        // Most of this day is still the equation, so the ceiling is lower than a measured day
        // earns. What varies is only how many sessions the picture is built from.
        let confidence = min(0.7, 0.2 + Double(withEnergy.count) / 20)
        let source = withEnergy.map(\.source).min { $0.rank < $1.rank } ?? .other("Apple Health")

        return MeasuredBurn(tdee: Int(total.rounded()),
                            activeKcal: Int(perDay.rounded()),
                            restingKcal: Int(prediction.restAndEverydayKcal.rounded()),
                            basis: .workoutsOnly,
                            days: windowDays,
                            sessions: withEnergy.count,
                            source: source,
                            confidence: confidence,
                            blended: blend(total, toward: prediction.tdee, confidence: confidence))
    }

    /// Held near the equation on purpose. A device that disagrees with it by more than this is more
    /// likely to have a wear or duplication problem than a metabolism worth believing.
    private static func blend(_ measured: Double, toward predicted: Double, confidence: Double) -> Int {
        let pulled = measured * confidence + predicted * (1 - confidence)
        let held = min(max(pulled, predicted * 0.7), predicted * 1.5)
        return Int((held / 10).rounded() * 10)
    }

    /// What Plate should believe about the burn before the scale and the food log get a vote.
    ///
    /// This is the right place for a wearable's number and the only place for it. Measuring your
    /// intake against what the trend line did is a genuine energy balance measurement and outranks
    /// any device model, so `TrendEngine.adaptiveTDEE` keeps the last word. What a wearable
    /// improves is the starting belief that measurement is blended against while the record is
    /// still short, which is otherwise an equation that has never met you.
    static func prior(measured: MeasuredBurn?, predictedTDEE: Double) -> Double {
        guard let measured else { return predictedTDEE }
        return Double(measured.blended)
    }

    // MARK: Training

    struct Workout: Equatable, Identifiable {
        var id: UUID
        var date: Date
        var end: Date
        var kind: String
        var minutes: Int
        /// Nil when the source recorded a session without an energy figure.
        var kcal: Int?
        var source: Source
    }

    /// A run logged by a watch and by a band is one run.
    ///
    /// Sessions that overlap in time collapse to the one from the source Plate trusts most, so a
    /// week does not look twice as busy as it was and its calories are not counted twice.
    static func deduplicate(_ workouts: [Workout]) -> [Workout] {
        var kept: [Workout] = []
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            if let index = kept.firstIndex(where: { $0.date < workout.end && $0.end > workout.date }) {
                if workout.source.rank < kept[index].source.rank { kept[index] = workout }
            } else {
                kept.append(workout)
            }
        }
        return kept.sorted { $0.date > $1.date }
    }

    struct TrainingWeek: Equatable {
        var sessions: Double
        var averageMinutes: Int
        var kcalPerDay: Int
    }

    /// What Health says a normal week looks like, in the same terms the setup questions ask for,
    /// so the two can be put beside each other and the user can decide which is right.
    static func trainingWeek(_ workouts: [Workout], overDays days: Int) -> TrainingWeek? {
        guard days > 0, !workouts.isEmpty else { return nil }
        // Anything shorter than this is a stray auto detected walk rather than a session, and
        // counting it would make the weekly figure look busier than the week was.
        let sessions = workouts.filter { $0.minutes >= 10 }
        guard !sessions.isEmpty else { return nil }

        let weeks = Double(days) / 7
        let totalMinutes = sessions.reduce(0) { $0 + $1.minutes }
        let totalKcal = sessions.reduce(0) { $0 + ($1.kcal ?? 0) }
        return TrainingWeek(sessions: (Double(sessions.count) / weeks * 10).rounded() / 10,
                            averageMinutes: Int((Double(totalMinutes) / Double(sessions.count)).rounded()),
                            kcalPerDay: Int((Double(totalKcal) / Double(days)).rounded()))
    }

    /// Plain names for the activity types worth naming. Anything else is just a workout, which is
    /// honest and reads better than an enum case. The cases are matched rather than their raw
    /// values, because guessing at the numbers is how you end up calling a swim a golf round.
    static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running, .trackAndField: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining: return "Strength training"
        case .functionalStrengthTraining: return "Functional strength"
        case .highIntensityIntervalTraining: return "Interval training"
        case .swimming, .swimBikeRun: return "Swimming"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .yoga: return "Yoga"
        case .coreTraining: return "Core training"
        case .hiking: return "Hiking"
        case .cardioDance, .socialDance: return "Dance"
        case .boxing: return "Boxing"
        case .kickboxing: return "Kickboxing"
        case .tennis: return "Tennis"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .golf: return "Golf"
        case .pilates: return "Pilates"
        case .stairClimbing, .stairs: return "Stair climbing"
        case .crossTraining: return "Cross training"
        case .mixedCardio: return "Mixed cardio"
        case .climbing: return "Climbing"
        case .cooldown, .preparationAndRecovery: return "Recovery"
        default: return "Workout"
        }
    }

    // MARK: Recovery context

    /// Numbers Plate shows and does not interpret. None of them change a calorie target, and the
    /// app has no business telling anybody what their heart rate variability means.
    struct Recovery: Equatable {
        var sleepHours: Double?
        var sleepSource: Source?
        var sleepEnd: Date?
        var restingHeartRate: Int?
        var restingHeartRateSource: Source?
        var hrvMs: Int?
        var hrvSource: Source?
        var hrvDate: Date?
        var respiratoryRate: Double?
        var respiratoryRateSource: Source?

        var isEmpty: Bool {
            sleepHours == nil && restingHeartRate == nil && hrvMs == nil && respiratoryRate == nil
        }
    }

    /// Minutes covered by these intervals, counting any overlap once.
    ///
    /// Whoop writes a sample per sleep stage and a watch writes its own beside it. Adding the
    /// durations up would invent hours that nobody slept.
    static func unionMinutes(_ intervals: [(start: Date, end: Date)]) -> Double {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total = 0.0
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current.end = max(current.end, next.end)
            } else {
                total += current.end.timeIntervalSince(current.start)
                current = next
            }
        }
        total += current.end.timeIntervalSince(current.start)
        return total / 60
    }

    // MARK: What was last read

    /// Enough to tell the user the switch is doing something, and enough to tell them when it is
    /// not. An absent wearable leaves every field nil and the UI shows nothing.
    struct Snapshot: Equatable {
        var readAt: Date?
        var burn: MeasuredBurn?
        var training: TrainingWeek?
        var workouts: [Workout] = []
        var recovery = Recovery()

        var hasAnything: Bool { burn != nil || training != nil || !recovery.isEmpty }
    }
}
