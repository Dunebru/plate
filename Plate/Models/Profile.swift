import Foundation
import SwiftData

// MARK: Who you are

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

/// Everyday movement, not workouts. Training is asked separately so it is never counted twice.
/// The multipliers are physical activity levels from the FAO, WHO and UNU energy report.
enum DailyActivity: String, Codable, CaseIterable, Identifiable {
    case desk, light, onFeet, physical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .desk: return "Mostly seated"
        case .light: return "Up and down"
        case .onFeet: return "On my feet"
        case .physical: return "Physical work"
        }
    }
    var detail: String {
        switch self {
        case .desk: return "Desk job or studying. Under 5,000 steps on a normal day."
        case .light: return "Some walking, errands, light chores. Around 5,000 to 8,000 steps."
        case .onFeet: return "Teaching, nursing, retail, parenting small children. 8,000 to 12,000 steps."
        case .physical: return "Construction, warehouse, farming. On your feet and carrying things all day."
        }
    }
    var symbol: String {
        switch self {
        case .desk: return "chair.lounge.fill"
        case .light: return "figure.walk"
        case .onFeet: return "figure.walk.motion"
        case .physical: return "hammer.fill"
        }
    }
    /// Physical activity level before any purposeful training is added.
    var pal: Double {
        switch self {
        case .desk: return 1.25
        case .light: return 1.40
        case .onFeet: return 1.55
        case .physical: return 1.70
        }
    }
}

/// Kept so older profiles keep working. New profiles use `DailyActivity` plus training details.
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

/// What the training actually is. The MET values are from the Compendium of Physical Activities
/// and are used net of rest, because resting burn is already counted in the BMR.
enum TrainingStyle: String, Codable, CaseIterable, Identifiable {
    case none, strength, cardio, hiit, sports, yoga, walking, mixed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Not training yet"
        case .strength: return "Lifting weights"
        case .cardio: return "Running or cycling"
        case .hiit: return "Intervals or CrossFit"
        case .sports: return "Team sport"
        case .yoga: return "Yoga or pilates"
        case .walking: return "Walking"
        case .mixed: return "A bit of everything"
        }
    }
    var symbol: String {
        switch self {
        case .none: return "zzz"
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .hiit: return "bolt.fill"
        case .sports: return "sportscourt.fill"
        case .yoga: return "figure.mind.and.body"
        case .walking: return "figure.walk"
        case .mixed: return "figure.mixed.cardio"
        }
    }
    /// Metabolic equivalent of task, moderate effort.
    var met: Double {
        switch self {
        case .none: return 1
        case .strength: return 5.0
        case .cardio: return 7.5
        case .hiit: return 8.0
        case .sports: return 7.0
        case .yoga: return 3.0
        case .walking: return 3.5
        case .mixed: return 6.0
        }
    }
    /// Whether this style builds the muscle that shapes a body part.
    var buildsMuscle: Bool { self == .strength || self == .hiit || self == .mixed }
}

enum TrainingExperience: String, Codable, CaseIterable, Identifiable {
    case none, beginner, intermediate, advanced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Never trained"
        case .beginner: return "Under a year"
        case .intermediate: return "One to three years"
        case .advanced: return "Over three years"
        }
    }
    /// Roughly how much muscle can be added in a month, in kilograms, at best.
    var monthlyMuscleKg: Double {
        switch self {
        case .none, .beginner: return 0.9
        case .intermediate: return 0.45
        case .advanced: return 0.23
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case lose, maintain, gain, recomp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lose: return "Lose fat"
        case .maintain: return "Maintain"
        case .gain: return "Build muscle"
        case .recomp: return "Lose fat and build muscle"
        }
    }
    var short: String {
        switch self {
        case .lose: return "Lose"
        case .maintain: return "Maintain"
        case .gain: return "Gain"
        case .recomp: return "Recomp"
        }
    }
    var symbol: String {
        switch self {
        case .lose: return "arrow.down.right"
        case .maintain: return "equal"
        case .gain: return "arrow.up.right"
        case .recomp: return "arrow.triangle.swap"
        }
    }
    var detail: String {
        switch self {
        case .lose: return "A calorie deficit, with enough protein to keep the muscle you have."
        case .maintain: return "Hold your weight steady and eat well."
        case .gain: return "A small surplus so the weight you add is mostly muscle."
        case .recomp: return "Eat at maintenance and train hard. Slower, but the scale barely moves while your shape does."
        }
    }
    var changesWeight: Bool { self == .lose || self == .gain }
}

enum DietStyle: String, Codable, CaseIterable, Identifiable {
    case balanced, highProtein, lowCarb, keto, mediterranean, vegetarian, vegan, pescatarian
    var id: String { rawValue }
    var label: String {
        switch self {
        case .balanced: return "No restrictions"
        case .highProtein: return "High protein"
        case .lowCarb: return "Low carb"
        case .keto: return "Keto"
        case .mediterranean: return "Mediterranean"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        }
    }
    var detail: String {
        switch self {
        case .balanced: return "Protein, carbs and fat in normal proportions."
        case .highProtein: return "More protein, which keeps you full and protects muscle."
        case .lowCarb: return "Carbs kept low, fat fills the gap."
        case .keto: return "Carbs under about 25 g so the body runs on fat."
        case .mediterranean: return "Olive oil, fish, vegetables and whole grains."
        case .vegetarian: return "No meat or fish."
        case .vegan: return "No animal products at all."
        case .pescatarian: return "Fish but no meat."
        }
    }
    /// Plant based eating needs a little more protein because plant sources digest less completely
    /// and carry less leucine per gram.
    var proteinBoost: Double {
        switch self {
        case .vegan: return 1.15
        case .vegetarian: return 1.10
        case .highProtein: return 1.10
        default: return 1
        }
    }
    /// Share of calories from fat. Carbs take whatever is left after protein and fat.
    var fatFraction: Double {
        switch self {
        case .keto: return 0.70
        case .lowCarb: return 0.45
        case .mediterranean: return 0.38
        default: return 0.28
        }
    }
    var carbCapGrams: Double? {
        switch self {
        case .keto: return 25
        case .lowCarb: return 100
        default: return nil
        }
    }
}

/// A part of the body someone wants to change. Fat cannot be lost from one spot on purpose, so the
/// app is careful to separate what training can change from what only overall fat loss can.
enum BodyArea: String, Codable, CaseIterable, Identifiable {
    case chest, midsection, arms, shoulders, back, glutes, legs, faceAndNeck, overall
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chest: return "Chest"
        case .midsection: return "Belly and waist"
        case .arms: return "Arms"
        case .shoulders: return "Shoulders"
        case .back: return "Back"
        case .glutes: return "Glutes"
        case .legs: return "Legs"
        case .faceAndNeck: return "Face and neck"
        case .overall: return "Overall shape"
        }
    }
    var symbol: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .midsection: return "figure.core.training"
        case .arms: return "dumbbell.fill"
        case .shoulders: return "figure.arms.open"
        case .back: return "figure.rower"
        case .glutes: return "figure.cross.training"
        case .legs: return "figure.run"
        case .faceAndNeck: return "face.smiling"
        case .overall: return "figure.stand"
        }
    }
}

enum AreaGoal: String, Codable, CaseIterable, Identifiable {
    case leaner, bigger, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leaner: return "Leaner there"
        case .bigger: return "More muscle there"
        case .both: return "Both"
        }
    }
}

/// What has got in the way before. Used to pick which nudges the app shows, nothing else.
enum Obstacle: String, Codable, CaseIterable, Identifiable {
    case consistency, cravings, socialEating, busy, lateNight, portions, alcohol, unsure, motivation
    var id: String { rawValue }
    var label: String {
        switch self {
        case .consistency: return "Staying consistent"
        case .cravings: return "Cravings and snacking"
        case .socialEating: return "Eating out and takeaways"
        case .busy: return "No time to cook"
        case .lateNight: return "Late night eating"
        case .portions: return "Portion sizes"
        case .alcohol: return "Drinking"
        case .unsure: return "Not knowing what to eat"
        case .motivation: return "Losing motivation"
        }
    }
    var tip: String {
        switch self {
        case .consistency: return "Log the first meal of the day before you eat it. Days that start logged tend to finish logged."
        case .cravings: return "Cravings fade faster on a full stomach. Protein and fiber at each meal do more than willpower."
        case .socialEating: return "Log restaurant meals from the photo and round up. An estimate you keep beats a perfect number you skip."
        case .busy: return "Cook once, eat twice. Plate keeps your saved foods one tap away."
        case .lateNight: return "Leave a few hundred calories unspent for the evening. Rollover is in Settings if you want yesterday's leftovers too."
        case .portions: return "Weigh the three foods you eat most for one week. After that you will guess them well for life."
        case .alcohol: return "Every drink is roughly 100 to 150 calories with nothing to show for it. Log it before, not after."
        case .unsure: return "Hit protein and fiber first. The rest sorts itself out."
        case .motivation: return "Watch the trend line, not the scale. It only moves the way you are actually going."
        }
    }
}

enum MealPattern: String, Codable, CaseIterable, Identifiable {
    case two, three, threePlusSnacks, grazing, oneMeal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .two: return "Two meals"
        case .three: return "Three meals"
        case .threePlusSnacks: return "Three meals and snacks"
        case .grazing: return "Lots of small meals"
        case .oneMeal: return "One meal a day"
        }
    }
    var mealCount: Int {
        switch self {
        case .two: return 2
        case .three: return 3
        case .threePlusSnacks: return 4
        case .grazing: return 5
        case .oneMeal: return 1
        }
    }
}

/// Whether every day gets the same calories, or some days get more.
enum CalorieCycling: String, Codable, CaseIterable, Identifiable {
    case even, trainingDays, weekends
    var id: String { rawValue }
    var label: String {
        switch self {
        case .even: return "The same every day"
        case .trainingDays: return "More on training days"
        case .weekends: return "More at the weekend"
        }
    }
    var detail: String {
        switch self {
        case .even: return "One number to remember."
        case .trainingDays: return "Eat more when you train, less when you rest. Same weekly total."
        case .weekends: return "Save a little Monday to Friday so Saturday and Sunday have room."
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String { self == .metric ? "Metric" : "Imperial" }
}

// MARK: The profile

@Model
final class Profile {
    var createdAt: Date = Date()

    // Body
    var sexRaw: String = Sex.male.rawValue
    var birthYear: Int = 1995
    var birthDate: Date? = nil
    var heightCm: Double = 175
    var weightKg: Double = 75
    var unitsRaw: String = UnitSystem.metric.rawValue

    // Composition, all optional because a tape measure is never required
    var neckCm: Double? = nil
    var waistCm: Double? = nil
    var hipCm: Double? = nil
    var enteredBodyFat: Double? = nil

    // Movement
    var activityRaw: String = ActivityLevel.light.rawValue
    var dailyActivityRaw: String? = nil
    var trainingDaysPerWeek: Int = 0
    var trainingMinutes: Int = 45
    var trainingStyleRaw: String = TrainingStyle.none.rawValue
    var experienceRaw: String = TrainingExperience.none.rawValue

    // Goal
    var goalRaw: String = Goal.maintain.rawValue
    var targetWeightKg: Double = 75
    var targetBodyFat: Double? = nil
    /// Kilograms per week, always positive. The direction comes from the goal.
    var paceKgPerWeek: Double = 0.5

    // Eating
    var dietRaw: String = DietStyle.balanced.rawValue
    var mealPatternRaw: String = MealPattern.three.rawValue
    var cyclingRaw: String = CalorieCycling.even.rawValue
    var avoidsRaw: String = ""
    var drinksPerWeek: Int = 0

    // What they want to change, and what gets in the way
    var focusAreasRaw: String = ""
    var areaGoalRaw: String = AreaGoal.leaner.rawValue
    var obstaclesRaw: String = ""

    // Targets
    var calorieTarget: Int = 2000
    var proteinTarget: Int = 150
    var carbTarget: Int = 200
    var fatTarget: Int = 65
    var fiberTarget: Int = 28
    var waterMl: Int = 2500
    /// Set when the user edits a target by hand, so recalculating does not quietly undo their choice.
    var targetsEditedByUser: Bool = false

    // Preferences
    var addExerciseCalories: Bool = false
    var rolloverCalories: Bool = false
    var writeToHealth: Bool = true
    var showBodyTab: Bool = true
    var onboarded: Bool = false

    init() {}

    // MARK: Typed accessors

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }
    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .light }
        set { activityRaw = newValue.rawValue }
    }
    /// Nil on profiles made before the split between everyday movement and training.
    var dailyActivity: DailyActivity? {
        get { dailyActivityRaw.flatMap(DailyActivity.init(rawValue:)) }
        set { dailyActivityRaw = newValue?.rawValue }
    }
    var trainingStyle: TrainingStyle {
        get { TrainingStyle(rawValue: trainingStyleRaw) ?? .none }
        set { trainingStyleRaw = newValue.rawValue }
    }
    var experience: TrainingExperience {
        get { TrainingExperience(rawValue: experienceRaw) ?? .none }
        set { experienceRaw = newValue.rawValue }
    }
    var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }
    var diet: DietStyle {
        get { DietStyle(rawValue: dietRaw) ?? .balanced }
        set { dietRaw = newValue.rawValue }
    }
    var mealPattern: MealPattern {
        get { MealPattern(rawValue: mealPatternRaw) ?? .three }
        set { mealPatternRaw = newValue.rawValue }
    }
    var cycling: CalorieCycling {
        get { CalorieCycling(rawValue: cyclingRaw) ?? .even }
        set { cyclingRaw = newValue.rawValue }
    }
    var areaGoal: AreaGoal {
        get { AreaGoal(rawValue: areaGoalRaw) ?? .leaner }
        set { areaGoalRaw = newValue.rawValue }
    }
    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }
    var focusAreas: [BodyArea] {
        get { Profile.decode(focusAreasRaw) }
        set { focusAreasRaw = Profile.encode(newValue) }
    }
    var obstacles: [Obstacle] {
        get { Profile.decode(obstaclesRaw) }
        set { obstaclesRaw = Profile.encode(newValue) }
    }
    var avoids: [String] {
        get { avoidsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        set { avoidsRaw = newValue.joined(separator: ", ") }
    }

    private static func decode<T: RawRepresentable>(_ raw: String) -> [T] where T.RawValue == String {
        raw.split(separator: ",").compactMap { T(rawValue: String($0)) }
    }
    private static func encode<T: RawRepresentable>(_ values: [T]) -> String where T.RawValue == String {
        values.map(\.rawValue).joined(separator: ",")
    }

    var age: Int {
        if let birthDate {
            let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
            return max(13, years)
        }
        return max(13, Calendar.current.component(.year, from: Date()) - birthYear)
    }

    // MARK: Derived body numbers

    var bodyFat: BodyComposition.Estimate? {
        BodyComposition.bestEstimate(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
                                     entered: enteredBodyFat, neckCm: neckCm, waistCm: waistCm, hipCm: hipCm)
    }

    /// Only the numbers good enough to feed the calorie math. A BMI guess is not.
    var trustedBodyFat: Double? {
        guard let bodyFat, bodyFat.source != .estimated else { return nil }
        return bodyFat.percent
    }

    var leanMassKg: Double? {
        bodyFat.map { BodyComposition.leanMassKg(weightKg: weightKg, bodyFatPercent: $0.percent) }
    }

    var bmi: Double { BodyComposition.bmi(weightKg: weightKg, heightCm: heightCm) }

    var inputs: NutritionMath.Inputs {
        .init(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
              activity: activity, goal: goal, paceKgPerWeek: paceKgPerWeek,
              bodyFatPercent: trustedBodyFat,
              dailyActivity: dailyActivity,
              trainingDaysPerWeek: trainingDaysPerWeek,
              trainingMinutes: trainingMinutes,
              trainingStyle: trainingStyle,
              experience: experience,
              diet: diet)
    }

    var plan: NutritionMath.Plan { NutritionMath.plan(for: inputs) }

    /// Recomputes every target from the current answers.
    func recalculateTargets() {
        let plan = self.plan
        calorieTarget = plan.calories
        proteinTarget = plan.protein
        carbTarget = plan.carbs
        fatTarget = plan.fat
        fiberTarget = plan.fiber
        waterMl = plan.waterMl
        targetsEditedByUser = false
    }
}
