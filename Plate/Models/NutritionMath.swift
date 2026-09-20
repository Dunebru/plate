import Foundation

/// Every number the app puts in front of you comes from here.
///
/// Three things make this better than the usual calculator. Resting burn uses lean mass when a body
/// fat figure exists, because two people at the same weight do not burn the same. Everyday movement
/// and training are counted separately instead of guessed with one blunt multiplier. And the
/// forecast recomputes your burn every week as you get lighter, so it slows down the way real
/// weight loss does rather than drawing a straight line.
///
/// Sources for all of it are in the Sources screen, reachable from Settings.
enum NutritionMath {

    struct Inputs: Equatable {
        var sex: Sex
        var age: Int
        var heightCm: Double
        var weightKg: Double
        /// Kept for profiles made before everyday movement and training were asked separately.
        var activity: ActivityLevel
        var goal: Goal
        /// Kilograms per week, always positive.
        var paceKgPerWeek: Double
        var bodyFatPercent: Double? = nil
        var dailyActivity: DailyActivity? = nil
        var trainingDaysPerWeek: Int = 0
        var trainingMinutes: Int = 45
        var trainingStyle: TrainingStyle = .none
        var experience: TrainingExperience = .none
        var diet: DietStyle = .balanced
    }

    /// Energy in a kilogram of body weight lost or gained. An average, not a constant: real tissue
    /// is a mix of fat and lean, and the ratio shifts as you get leaner.
    static let kcalPerKg = 7700.0

    // MARK: Resting burn

    /// Mifflin-St Jeor. The most accurate prediction equation when body composition is unknown.
    static func mifflinStJeor(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Katch-McArdle. Uses lean mass, so it does not care about sex or age, and it beats every
    /// weight based equation once you know your body fat.
    static func katchMcArdle(leanMassKg: Double) -> Double { 370 + 21.6 * leanMassKg }

    static func bmr(_ i: Inputs) -> Double {
        if let bf = i.bodyFatPercent, bf > 3, bf < 60 {
            return katchMcArdle(leanMassKg: BodyComposition.leanMassKg(weightKg: i.weightKg, bodyFatPercent: bf))
        }
        return mifflinStJeor(sex: i.sex, age: i.age, heightCm: i.heightCm, weightKg: i.weightKg)
    }

    static func bmrMethod(_ i: Inputs) -> String {
        if let bf = i.bodyFatPercent, bf > 3, bf < 60 { return "Katch-McArdle, from your lean mass" }
        return "Mifflin-St Jeor"
    }

    // MARK: Daily burn

    /// Calories a training session costs above simply being alive. Resting burn is already counted
    /// in the BMR, so one metabolic equivalent is subtracted before converting.
    static func trainingKcalPerDay(_ i: Inputs) -> Double {
        guard i.trainingDaysPerWeek > 0, i.trainingMinutes > 0, i.trainingStyle != .none else { return 0 }
        let perMinute = (i.trainingStyle.met - 1) * 3.5 * i.weightKg / 200
        let weekly = perMinute * Double(i.trainingMinutes) * Double(min(i.trainingDaysPerWeek, 14))
        return weekly / 7
    }

    /// How many times resting burn you spend in a day, all in.
    static func activityFactor(_ i: Inputs) -> Double {
        guard let daily = i.dailyActivity else { return i.activity.multiplier }
        let resting = bmr(i)
        guard resting > 0 else { return daily.pal }
        return daily.pal + trainingKcalPerDay(i) / resting
    }

    static func tdee(_ i: Inputs) -> Double { bmr(i) * activityFactor(i) }

    // MARK: How fast is safe

    /// The most weight per week worth losing, as a share of body weight. Someone carrying a lot of
    /// fat can afford the top of the range. Someone already lean cannot: past this, the weight
    /// coming off is increasingly muscle (Garthe 2011, Helms 2014).
    static func maxWeeklyLossFraction(sex: Sex, bodyFatPercent: Double?) -> Double {
        guard let bf = bodyFatPercent else { return 0.010 }
        switch sex {
        case .male: return bf >= 25 ? 0.011 : (bf >= 18 ? 0.0085 : 0.006)
        case .female: return bf >= 32 ? 0.011 : (bf >= 25 ? 0.0085 : 0.006)
        }
    }

    /// The most weight per week worth gaining. Muscle has a speed limit, and everything above it
    /// arrives as fat.
    static func maxWeeklyGainFraction(experience: TrainingExperience) -> Double {
        switch experience {
        case .none, .beginner: return 0.005
        case .intermediate: return 0.0035
        case .advanced: return 0.0025
        }
    }

    /// The pace actually used, after the safety caps. Returns kilograms per week, always positive.
    static func cappedPace(_ i: Inputs) -> Double {
        guard i.goal.changesWeight else { return 0 }
        let fraction = i.goal == .lose
            ? maxWeeklyLossFraction(sex: i.sex, bodyFatPercent: i.bodyFatPercent)
            : maxWeeklyGainFraction(experience: i.experience)
        return min(max(i.paceKgPerWeek, 0), fraction * i.weightKg)
    }

    /// The lowest daily calories to put in front of anyone without medical supervision (NHLBI).
    static func calorieFloor(sex: Sex) -> Double { sex == .male ? 1500 : 1200 }

    // MARK: The plan

    struct Plan: Equatable {
        var bmr: Int
        var tdee: Int
        var calories: Int
        var protein: Int
        var carbs: Int
        var fat: Int
        var fiber: Int = 28
        var waterMl: Int = 2500
        /// Signed: negative in a deficit, positive in a surplus.
        var dailyDelta: Int = 0
        /// Kilograms per week the plan actually aims for, after the safety caps.
        var paceKgPerWeek: Double = 0
        var method: String = ""
        /// Set when the pace asked for was faster than is sensible, or the floor caught the target.
        var note: String? = nil

        var proteinKcal: Int { protein * 4 }
        var carbKcal: Int { carbs * 4 }
        var fatKcal: Int { fat * 9 }
    }

    static func plan(for i: Inputs) -> Plan {
        let resting = bmr(i)
        let burn = tdee(i)
        let pace = cappedPace(i)
        var note: String?

        var delta = 0.0
        switch i.goal {
        case .lose: delta = -pace * kcalPerKg / 7
        case .gain: delta = pace * kcalPerKg / 7
        case .maintain: delta = 0
        case .recomp:
            // A small deficit is enough when training is hard and protein is high. Muscle is built
            // from training and protein, not from surplus calories.
            delta = -0.08 * burn
        }

        // Never take away more than a quarter of the day's burn: bigger cuts mean lost muscle,
        // worse training, and a plan nobody sticks to.
        let maxCut = 0.25 * burn
        if delta < -maxCut {
            delta = -maxCut
            note = "Eased to a steadier pace. Cutting more than a quarter of your daily burn costs muscle and rarely lasts."
        }
        if i.goal.changesWeight, pace < i.paceKgPerWeek - 0.001 {
            note = i.goal == .lose
                ? "Capped at a safe rate for your size. Faster than this and the scale moves, but muscle goes with it."
                : "Capped at the rate muscle can actually be built. Anything quicker is mostly fat."
        }

        var calories = burn + delta
        let floor = calorieFloor(sex: i.sex)
        if calories < floor {
            calories = floor
            note = "Held at the lowest daily amount considered safe without medical supervision."
        }

        let macros = macros(calories: calories, inputs: i)
        return Plan(bmr: Int(resting.rounded()),
                    tdee: Int(burn.rounded()),
                    calories: Int((calories / 10).rounded() * 10),
                    protein: macros.protein,
                    carbs: macros.carbs,
                    fat: macros.fat,
                    fiber: fiberTarget(calories: calories),
                    waterMl: waterTarget(weightKg: i.weightKg, trainingDays: i.trainingDaysPerWeek),
                    dailyDelta: Int((calories - burn).rounded()),
                    paceKgPerWeek: pace,
                    method: bmrMethod(i),
                    note: note)
    }

    // MARK: Macros

    /// Protein per kilogram. Measured against lean mass when it is known, because fat does not need
    /// feeding, and against body weight otherwise.
    static func proteinPerKg(goal: Goal, usingLeanMass: Bool) -> Double {
        if usingLeanMass {
            switch goal {
            case .lose: return 2.4
            case .recomp: return 2.3
            case .gain: return 2.1
            case .maintain: return 1.9
            }
        }
        switch goal {
        case .lose: return 2.0
        case .recomp: return 1.9
        case .gain: return 1.8
        case .maintain: return 1.6
        }
    }

    static func macros(calories: Double, inputs i: Inputs) -> (protein: Int, carbs: Int, fat: Int) {
        let lean = i.bodyFatPercent.map { BodyComposition.leanMassKg(weightKg: i.weightKg, bodyFatPercent: $0) }
        let perKg = proteinPerKg(goal: i.goal, usingLeanMass: lean != nil) * i.diet.proteinBoost
        var protein = perKg * (lean ?? i.weightKg)
        // Past 40% of calories protein crowds out the carbs that fuel training, and under 1.2 g per
        // kilogram it stops protecting muscle.
        protein = min(protein, calories * 0.40 / 4)
        protein = max(protein, 1.2 * i.weightKg)

        var fat = calories * i.diet.fatFraction / 9
        fat = max(fat, 0.5 * i.weightKg)   // hormones need dietary fat

        var carbs = (calories - protein * 4 - fat * 9) / 4
        if let cap = i.diet.carbCapGrams, carbs > cap {
            carbs = cap
            fat = max((calories - protein * 4 - carbs * 4) / 9, 0.5 * i.weightKg)
        }
        if carbs < 30 {
            // Brain and training need some carbohydrate unless the diet is deliberately ketogenic.
            carbs = i.diet == .keto ? max(carbs, 20) : 50
            fat = max((calories - protein * 4 - carbs * 4) / 9, 0.4 * i.weightKg)
        }
        return (Int(protein.rounded()), Int(max(carbs, 0).rounded()), Int(fat.rounded()))
    }

    /// 14 g of fiber per 1,000 calories, the Institute of Medicine figure.
    static func fiberTarget(calories: Double) -> Int { Int((calories / 1000 * 14).rounded()) }

    /// About 35 ml per kilogram, plus half a litre for each training day spread across the week.
    static func waterTarget(weightKg: Double, trainingDays: Int) -> Int {
        let base = weightKg * 35 + Double(min(trainingDays, 7)) * 500 / 7
        return Int((base / 100).rounded() * 100)
    }

    // MARK: Days that are not all the same

    struct DaySplit: Equatable {
        var higher: Int
        var lower: Int
        var higherDays: Int
        var label: String
    }

    /// Same weekly total, spread unevenly. Eating more around training is easier to stick to and
    /// gives the hard sessions something to run on.
    static func daySplit(calories: Int, cycling: CalorieCycling, trainingDaysPerWeek: Int) -> DaySplit? {
        let highDays: Int
        let label: String
        switch cycling {
        case .even: return nil
        case .trainingDays:
            highDays = trainingDaysPerWeek
            label = "Training days"
        case .weekends:
            highDays = 2
            label = "Saturday and Sunday"
        }
        guard highDays > 0, highDays < 7 else { return nil }
        let base = Double(calories)
        let spread = min(350, base * 0.15)
        let higher = base + spread * Double(7 - highDays) / 7
        let lower = base - spread * Double(highDays) / 7
        return DaySplit(higher: Int((higher / 10).rounded() * 10),
                        lower: Int((lower / 10).rounded() * 10),
                        higherDays: highDays,
                        label: label)
    }

    // MARK: Where the goal actually lands

    struct ProjectionPoint: Identifiable, Equatable {
        var id: Int { week }
        var week: Int
        var date: Date
        var weightKg: Double
        var bodyFatPercent: Double?
        var leanMassKg: Double?
    }

    /// Week by week forecast that recomputes your burn as your body changes.
    ///
    /// Holding calories steady while you get lighter means the gap between what you burn and what
    /// you eat narrows every week, so loss slows and eventually stops. That is what actually
    /// happens, and it is why a straight line drawn from your first week always overpromises.
    static func projection(for i: Inputs, calorieTarget: Int, weeks: Int = 52, from start: Date = Date()) -> [ProjectionPoint] {
        var weight = i.weightKg
        var bodyFat = i.bodyFatPercent
        var lean = bodyFat.map { BodyComposition.leanMassKg(weightKg: weight, bodyFatPercent: $0) }
        let startWeight = weight
        let cal = Calendar.current
        var points = [ProjectionPoint(week: 0, date: start, weightKg: weight, bodyFatPercent: bodyFat, leanMassKg: lean)]

        for week in 1...max(1, weeks) {
            var step = i
            step.weightKg = weight
            step.bodyFatPercent = bodyFat
            let burn = tdee(step) * adaptation(startWeightKg: startWeight, currentWeightKg: weight)
            let dailyDelta = Double(calorieTarget) - burn
            let change = dailyDelta * 7 / kcalPerKg

            if var leanNow = lean, var fatNow = bodyFat.map({ BodyComposition.fatMassKg(weightKg: weight, bodyFatPercent: $0) }) {
                let fatShare = change < 0 ? fatLossShare(i) : 1 - muscleGainShare(i, weeklyGainKg: change)
                fatNow = max(fatNow + change * fatShare, 0.02 * weight)
                leanNow = max(leanNow + change * (1 - fatShare), 0)
                lean = leanNow
                weight = leanNow + fatNow
                bodyFat = weight > 0 ? fatNow / weight * 100 : nil
            } else {
                weight += change
            }

            guard weight > 25, weight.isFinite else { break }
            points.append(ProjectionPoint(week: week,
                                          date: cal.date(byAdding: .weekOfYear, value: week, to: start) ?? start,
                                          weightKg: weight, bodyFatPercent: bodyFat, leanMassKg: lean))
            if abs(change) < 0.015 { break }   // settled at the new maintenance
        }
        return points
    }

    /// Losing weight lowers burn by a little more than the smaller body explains, and the gap grows
    /// with how much has come off. Capped at a tenth, which is the top of what the research shows.
    static func adaptation(startWeightKg: Double, currentWeightKg: Double) -> Double {
        guard startWeightKg > 0 else { return 1 }
        let lostPercent = max(0, (startWeightKg - currentWeightKg) / startWeightKg * 100)
        return 1 - min(0.10, lostPercent * 0.006)
    }

    /// How much of the weight lost comes from fat rather than muscle. Enough protein and real
    /// resistance training are what keep this number high.
    static func fatLossShare(_ i: Inputs) -> Double {
        var share = 0.75
        if i.trainingStyle.buildsMuscle, i.trainingDaysPerWeek >= 2 { share += 0.12 }
        else if i.trainingDaysPerWeek >= 2 { share += 0.04 }
        if i.goal == .lose || i.goal == .recomp { share += 0.03 }
        return min(share, 0.95)
    }

    /// How much of the weight gained is muscle rather than fat, limited by how fast muscle can be
    /// built at this training age.
    static func muscleGainShare(_ i: Inputs, weeklyGainKg: Double) -> Double {
        guard weeklyGainKg > 0 else { return 0 }
        guard i.trainingStyle.buildsMuscle, i.trainingDaysPerWeek >= 2 else { return 0.15 }
        let ceiling = i.experience.monthlyMuscleKg / 4.345     // per week
        return min(1, max(0, ceiling / weeklyGainKg))
    }

    /// The week the forecast first reaches the target weight, if it ever does.
    static func projectedGoalDate(for i: Inputs, calorieTarget: Int, targetKg: Double, from start: Date = Date()) -> Date? {
        let points = projection(for: i, calorieTarget: calorieTarget, weeks: 104, from: start)
        guard let first = points.first else { return nil }
        let losing = targetKg < first.weightKg
        return points.first { losing ? $0.weightKg <= targetKg : $0.weightKg >= targetKg }?.date
    }

    /// Weeks to the goal at the chosen pace, ignoring the slowdown. Useful as the headline number
    /// people expect; `projectedGoalDate` is the honest one.
    static func weeksToGoal(_ i: Inputs, targetKg: Double) -> Double? {
        guard i.goal.changesWeight, i.paceKgPerWeek > 0 else { return nil }
        return abs(targetKg - i.weightKg) / i.paceKgPerWeek
    }

    // MARK: Checking the plan against reality

    struct RealityCheck: Equatable {
        var days: Int
        var averageIntake: Int
        var weightChangeKg: Double
        var impliedTDEE: Int
        var suggestedCalories: Int
    }

    /// What the scale says your maintenance really is, from what you logged and what you weighed.
    static func realityCheck(intakeByDay: [Double], startWeightKg: Double, endWeightKg: Double, days: Int,
                             goal: Goal, paceKgPerWeek: Double) -> RealityCheck? {
        guard days >= 14, intakeByDay.count >= 10 else { return nil }
        let avg = intakeByDay.reduce(0, +) / Double(intakeByDay.count)
        let change = endWeightKg - startWeightKg
        let implied = avg - change * kcalPerKg / Double(days)
        let dailyDelta = paceKgPerWeek * kcalPerKg / 7
        let suggested: Double
        switch goal {
        case .lose: suggested = implied - dailyDelta
        case .gain: suggested = implied + dailyDelta
        case .maintain: suggested = implied
        case .recomp: suggested = implied * 0.92
        }
        return RealityCheck(days: days, averageIntake: Int(avg.rounded()), weightChangeKg: change,
                            impliedTDEE: Int(implied.rounded()), suggestedCalories: Int((suggested / 10).rounded() * 10))
    }

    // MARK: Small helpers kept for older call sites

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        BodyComposition.bmi(weightKg: weightKg, heightCm: heightCm)
    }
    static func bmiLabel(_ bmi: Double) -> String { BodyComposition.bmiLabel(bmi) }
}

enum Units {
    static func kgToLb(_ kg: Double) -> Double { kg * 2.2046226218 }
    static func lbToKg(_ lb: Double) -> Double { lb / 2.2046226218 }
    static func cmToInches(_ cm: Double) -> Double { cm / 2.54 }
    static func inchesToCm(_ inches: Double) -> Double { inches * 2.54 }
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

    /// Tape measurements, which imperial users think of in plain inches rather than feet.
    static func lengthString(_ cm: Double, _ units: UnitSystem, decimals: Int = 1) -> String {
        switch units {
        case .metric: return String(format: "%.\(decimals)f cm", cm)
        case .imperial: return String(format: "%.\(decimals)f in", cmToInches(cm))
        }
    }

    static var weightUnit: (UnitSystem) -> String { { $0 == .metric ? "kg" : "lb" } }
}
