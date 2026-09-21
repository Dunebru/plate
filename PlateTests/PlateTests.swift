import XCTest
@testable import Plate

final class NutritionMathTests: XCTestCase {
    func testMifflinStJeor() {
        let male = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .sedentary, goal: .maintain, paceKgPerWeek: 0.5)
        XCTAssertEqual(NutritionMath.bmr(male), 1780, accuracy: 0.5)
        let female = NutritionMath.Inputs(sex: .female, age: 30, heightCm: 165, weightKg: 60, activity: .sedentary, goal: .maintain, paceKgPerWeek: 0.5)
        XCTAssertEqual(NutritionMath.bmr(female), 1320.25, accuracy: 0.5)
    }

    func testDeficitAndFloor() {
        var i = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .light, goal: .lose, paceKgPerWeek: 0.5)
        let plan = NutritionMath.plan(for: i)
        XCTAssertEqual(plan.tdee, Int((1780 * 1.375).rounded()))
        XCTAssertEqual(Double(plan.calories), 1780 * 1.375 - 550, accuracy: 10)
        XCTAssertEqual(plan.protein * 4 + plan.carbs * 4 + plan.fat * 9, plan.calories, accuracy: 40)

        i = NutritionMath.Inputs(sex: .female, age: 60, heightCm: 150, weightKg: 45, activity: .sedentary, goal: .lose, paceKgPerWeek: 1.0)
        XCTAssertEqual(NutritionMath.plan(for: i).calories, 1200)
    }

    func testWeeksToGoal() {
        let i = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .light, goal: .lose, paceKgPerWeek: 0.5)
        XCTAssertEqual(NutritionMath.weeksToGoal(i, targetKg: 75), 10)
    }

    func testRealityCheck() {
        let intake = Array(repeating: 2000.0, count: 14)
        let check = NutritionMath.realityCheck(intakeByDay: intake, startWeightKg: 80, endWeightKg: 79, days: 14, goal: .lose, paceKgPerWeek: 0.5)!
        XCTAssertEqual(check.impliedTDEE, 2550)
        XCTAssertEqual(check.suggestedCalories, 2000)
        XCTAssertNil(NutritionMath.realityCheck(intakeByDay: intake, startWeightKg: 80, endWeightKg: 79, days: 7, goal: .lose, paceKgPerWeek: 0.5))
    }

    func testUnits() {
        XCTAssertEqual(Units.kgToLb(1), 2.2046, accuracy: 0.001)
        let (f, i) = Units.cmToFeetInches(180)
        XCTAssertEqual(f, 5); XCTAssertEqual(i, 11)
        XCTAssertEqual(Units.feetInchesToCm(6, 0), 182.88, accuracy: 0.01)
    }
}

final class BodyCompositionTests: XCTestCase {
    func testNavyMethodMatchesPublishedFormula() {
        let male = BodyComposition.navyBodyFat(sex: .male, heightCm: 180, neckCm: 38, waistCm: 85, hipCm: nil)
        XCTAssertEqual(male!, 16.1, accuracy: 0.2)
        let female = BodyComposition.navyBodyFat(sex: .female, heightCm: 165, neckCm: 32, waistCm: 72, hipCm: 96)
        XCTAssertEqual(female!, 26.4, accuracy: 0.2)
    }

    func testNavyMethodRefusesImpossibleInput() {
        XCTAssertNil(BodyComposition.navyBodyFat(sex: .male, heightCm: 180, neckCm: 40, waistCm: 40, hipCm: nil))
        XCTAssertNil(BodyComposition.navyBodyFat(sex: .female, heightCm: 165, neckCm: 32, waistCm: 72, hipCm: nil), "women need a hip measurement")
        XCTAssertNil(BodyComposition.navyBodyFat(sex: .male, heightCm: 0, neckCm: 38, waistCm: 85, hipCm: nil))
    }

    func testBestEstimatePrefersEnteredThenTapeThenBMI() {
        let entered = BodyComposition.bestEstimate(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                                   entered: 14, neckCm: 38, waistCm: 85, hipCm: nil)
        XCTAssertEqual(entered?.source, .entered)
        XCTAssertEqual(entered?.percent, 14)
        let tape = BodyComposition.bestEstimate(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                                entered: nil, neckCm: 38, waistCm: 85, hipCm: nil)
        XCTAssertEqual(tape?.source, .tape)
        let guess = BodyComposition.bestEstimate(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                                 entered: nil, neckCm: nil, waistCm: nil, hipCm: nil)
        XCTAssertEqual(guess?.source, .estimated)
    }

    func testLeanMassAndFFMI() {
        XCTAssertEqual(BodyComposition.leanMassKg(weightKg: 80, bodyFatPercent: 20), 64, accuracy: 0.001)
        XCTAssertEqual(BodyComposition.fatMassKg(weightKg: 80, bodyFatPercent: 20), 16, accuracy: 0.001)
        XCTAssertEqual(BodyComposition.ffmi(leanMassKg: 64, heightCm: 180), 19.75, accuracy: 0.01)
        // The height adjustment leaves a 1.8 m frame untouched and lifts a shorter one.
        XCTAssertEqual(BodyComposition.normalizedFFMI(leanMassKg: 64, heightCm: 180), 19.75, accuracy: 0.01)
        XCTAssertGreaterThan(BodyComposition.normalizedFFMI(leanMassKg: 64, heightCm: 170),
                             BodyComposition.ffmi(leanMassKg: 64, heightCm: 170))
    }

    func testWaistToHeightAndHealthyRange() {
        XCTAssertEqual(BodyComposition.waistToHeight(waistCm: 90, heightCm: 180)!, 0.5, accuracy: 0.001)
        XCTAssertEqual(BodyComposition.waistToHeightLabel(0.45), "Healthy")
        XCTAssertEqual(BodyComposition.waistToHeightLabel(0.55), "Increased health risk")
        let range = BodyComposition.healthyWeightRange(heightCm: 180)
        XCTAssertEqual(range.lowerBound, 59.9, accuracy: 0.2)
        XCTAssertEqual(range.upperBound, 80.7, accuracy: 0.2)
    }

    func testWeightAtTargetBodyFatKeepsLeanMass() {
        // 80 kg at 20% is 64 kg of lean mass; holding that, 12% body fat means 72.7 kg.
        let target = BodyComposition.weightAtBodyFat(currentWeightKg: 80, currentBodyFat: 20, targetBodyFat: 12)
        XCTAssertEqual(target!, 72.7, accuracy: 0.1)
    }

    func testBandsNeverLeaveANumberHomeless() {
        for sex in Sex.allCases {
            let bands = BodyComposition.bands(for: sex)
            for percent in stride(from: 3.0, through: 55.0, by: 0.1) {
                guard let band = BodyComposition.band(for: percent, sex: sex) else {
                    return XCTFail("no band for \(percent) \(sex)")
                }
                // A number that falls in a gap between published ranges must take the band below it,
                // never the last one in the list.
                let expected = bands.last(where: { percent >= $0.range.lowerBound }) ?? bands[0]
                XCTAssertEqual(band.name, expected.name, "\(percent) percent \(sex) landed in \(band.name)")
            }
        }
    }

    func testGapsBetweenPublishedBandsRoundDown() {
        // 17.9 sits between the Fitness band ending at 17 and the Average band starting at 18.
        XCTAssertEqual(BodyComposition.band(for: 17.9, sex: .male)?.name, "Fitness")
        XCTAssertEqual(BodyComposition.band(for: 13.5, sex: .male)?.name, "Athletes")
        XCTAssertEqual(BodyComposition.band(for: 24.5, sex: .male)?.name, "Average")
        XCTAssertEqual(BodyComposition.band(for: 20.5, sex: .female)?.name, "Athletes")
        XCTAssertEqual(BodyComposition.band(for: 1.0, sex: .male)?.name, "Essential")
        XCTAssertEqual(BodyComposition.band(for: 65, sex: .male)?.name, "Above average")
    }
}

final class BurnTests: XCTestCase {
    private func male(_ extra: (inout NutritionMath.Inputs) -> Void = { _ in }) -> NutritionMath.Inputs {
        var i = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                     activity: .light, goal: .maintain, paceKgPerWeek: 0.5)
        extra(&i)
        return i
    }

    func testKatchMcArdleUsedOnceBodyFatIsKnown() {
        XCTAssertEqual(NutritionMath.bmr(male()), 1780, accuracy: 0.5)
        let known = male { $0.bodyFatPercent = 20 }
        XCTAssertEqual(NutritionMath.bmr(known), 370 + 21.6 * 64, accuracy: 0.5)
        XCTAssertTrue(NutritionMath.bmrMethod(known).contains("Katch"))
        XCTAssertTrue(NutritionMath.bmrMethod(male()).contains("Mifflin"))
    }

    func testTrainingBurnIsNetOfResting() {
        let lifter = male {
            $0.trainingStyle = .strength; $0.trainingDaysPerWeek = 4; $0.trainingMinutes = 60
        }
        // (5 - 1) METs x 3.5 x 80 kg / 200 = 5.6 kcal a minute, four hours a week, spread over seven days.
        XCTAssertEqual(NutritionMath.trainingKcalPerDay(lifter), 5.6 * 60 * 4 / 7, accuracy: 0.5)
        XCTAssertEqual(NutritionMath.trainingKcalPerDay(male()), 0, "no training means no training burn")
    }

    func testEverydayMovementAndTrainingAreCountedSeparately() {
        let deskOnly = male { $0.dailyActivity = .desk }
        XCTAssertEqual(NutritionMath.activityFactor(deskOnly), 1.25, accuracy: 0.001)
        let deskPlusGym = male {
            $0.dailyActivity = .desk; $0.trainingStyle = .strength
            $0.trainingDaysPerWeek = 4; $0.trainingMinutes = 60
        }
        let expected = 1.25 + (5.6 * 60 * 4 / 7) / 1780
        XCTAssertEqual(NutritionMath.activityFactor(deskPlusGym), expected, accuracy: 0.005)
        XCTAssertGreaterThan(NutritionMath.tdee(deskPlusGym), NutritionMath.tdee(deskOnly))
    }

    func testOlderProfilesKeepTheirSingleMultiplier() {
        XCTAssertEqual(NutritionMath.activityFactor(male()), ActivityLevel.light.multiplier, accuracy: 0.001)
    }
}

final class PaceAndPlanTests: XCTestCase {
    private func lean(_ goal: Goal, pace: Double) -> NutritionMath.Inputs {
        NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .light,
                             goal: goal, paceKgPerWeek: pace, bodyFatPercent: 12)
    }

    func testLeanPeopleAreCappedHarderThanHeavyOnes() {
        XCTAssertEqual(NutritionMath.maxWeeklyLossFraction(sex: .male, bodyFatPercent: 30), 0.011)
        XCTAssertEqual(NutritionMath.maxWeeklyLossFraction(sex: .male, bodyFatPercent: 12), 0.006)
        XCTAssertEqual(NutritionMath.maxWeeklyLossFraction(sex: .female, bodyFatPercent: 35), 0.011)
        XCTAssertEqual(NutritionMath.maxWeeklyLossFraction(sex: .female, bodyFatPercent: 20), 0.006)
        // A lean 80 kg man asking for a kilo a week is held to 0.48.
        XCTAssertEqual(NutritionMath.cappedPace(lean(.lose, pace: 1.0)), 0.48, accuracy: 0.001)
        XCTAssertNotNil(NutritionMath.plan(for: lean(.lose, pace: 1.0)).note)
    }

    func testGainIsCappedByHowFastMuscleCanBeBuilt() {
        var i = lean(.gain, pace: 1.0)
        i.experience = .advanced
        XCTAssertEqual(NutritionMath.cappedPace(i), 0.2, accuracy: 0.001)
        i.experience = .beginner
        XCTAssertEqual(NutritionMath.cappedPace(i), 0.4, accuracy: 0.001)
    }

    func testDeficitNeverExceedsAQuarterOfTheDailyBurn() {
        let heavy = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 140, activity: .sedentary,
                                         goal: .lose, paceKgPerWeek: 1.5, bodyFatPercent: 38)
        let plan = NutritionMath.plan(for: heavy)
        XCTAssertGreaterThanOrEqual(Double(plan.calories), Double(plan.tdee) * 0.74)
        XCTAssertNotNil(plan.note)
    }

    func testRecompSitsJustBelowMaintenance() {
        var i = lean(.recomp, pace: 0)
        i.trainingStyle = .strength
        let plan = NutritionMath.plan(for: i)
        XCTAssertLessThan(plan.calories, plan.tdee)
        XCTAssertGreaterThan(Double(plan.calories), Double(plan.tdee) * 0.88)
    }

    func testMacrosAlwaysAddUpAndRespectTheirFloors() {
        for goal in Goal.allCases {
            for diet in DietStyle.allCases {
                for bodyFat in [nil, 12.0, 35.0] as [Double?] {
                    var i = NutritionMath.Inputs(sex: .female, age: 34, heightCm: 165, weightKg: 70,
                                                 activity: .light, goal: goal, paceKgPerWeek: 0.5)
                    i.diet = diet
                    i.bodyFatPercent = bodyFat
                    let p = NutritionMath.plan(for: i)
                    let sum = p.proteinKcal + p.carbKcal + p.fatKcal
                    XCTAssertEqual(Double(sum), Double(p.calories), accuracy: 60, "\(goal) \(diet) \(String(describing: bodyFat))")
                    XCTAssertGreaterThanOrEqual(Double(p.fat), 0.4 * 70 - 1, "fat floor for hormones")
                    XCTAssertLessThanOrEqual(Double(p.proteinKcal), Double(p.calories) * 0.42)
                    XCTAssertGreaterThanOrEqual(Double(p.protein), 1.2 * 70 - 1)
                }
            }
        }
    }

    func testKetoAndLowCarbCapCarbohydrate() {
        var i = lean(.lose, pace: 0.4)
        i.diet = .keto
        XCTAssertLessThanOrEqual(NutritionMath.plan(for: i).carbs, 25)
        i.diet = .lowCarb
        XCTAssertLessThanOrEqual(NutritionMath.plan(for: i).carbs, 100)
        i.diet = .balanced
        XCTAssertGreaterThan(NutritionMath.plan(for: i).carbs, 100)
    }

    func testPlantBasedEatingGetsMoreProtein() {
        var omnivore = lean(.lose, pace: 0.4)
        var vegan = omnivore
        vegan.diet = .vegan
        omnivore.diet = .balanced
        XCTAssertGreaterThan(NutritionMath.plan(for: vegan).protein, NutritionMath.plan(for: omnivore).protein)
    }

    func testProteinIsMeasuredAgainstLeanMassWhenItIsKnown() {
        // Same weight, very different composition: the leaner body is asked for more protein.
        var lean = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 90, activity: .light,
                                        goal: .lose, paceKgPerWeek: 0.5, bodyFatPercent: 12)
        var heavy = lean
        heavy.bodyFatPercent = 35
        lean.diet = .balanced; heavy.diet = .balanced
        XCTAssertGreaterThan(NutritionMath.plan(for: lean).protein, NutritionMath.plan(for: heavy).protein)
    }

    func testFiberAndWaterFollowTheirGuidelines() {
        XCTAssertEqual(NutritionMath.fiberTarget(calories: 2000), 28)
        XCTAssertEqual(NutritionMath.waterTarget(weightKg: 80, trainingDays: 0), 2800)
        XCTAssertGreaterThan(NutritionMath.waterTarget(weightKg: 80, trainingDays: 5),
                             NutritionMath.waterTarget(weightKg: 80, trainingDays: 0))
    }

    func testDaySplitKeepsTheWeeklyTotal() {
        let split = NutritionMath.daySplit(calories: 2000, cycling: .trainingDays, trainingDaysPerWeek: 4)!
        XCTAssertGreaterThan(split.higher, 2000)
        XCTAssertLessThan(split.lower, 2000)
        let weekly = split.higher * 4 + split.lower * 3
        XCTAssertEqual(Double(weekly), 14000, accuracy: 70)
        XCTAssertNil(NutritionMath.daySplit(calories: 2000, cycling: .even, trainingDaysPerWeek: 4))
        XCTAssertNil(NutritionMath.daySplit(calories: 2000, cycling: .trainingDays, trainingDaysPerWeek: 0))
        XCTAssertNotNil(NutritionMath.daySplit(calories: 2000, cycling: .weekends, trainingDaysPerWeek: 0))
    }
}

final class ProjectionTests: XCTestCase {
    private let losing = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 95, activity: .light,
                                              goal: .lose, paceKgPerWeek: 0.5, bodyFatPercent: 28)

    func testLossSlowsDownInsteadOfRunningInAStraightLine() {
        let points = NutritionMath.projection(for: losing, calorieTarget: 2000, weeks: 40)
        XCTAssertGreaterThan(points.count, 10)
        let firstMonth = points[0].weightKg - points[4].weightKg
        let fourthMonth = points[12].weightKg - points[16].weightKg
        XCTAssertGreaterThan(firstMonth, 0, "should be losing")
        XCTAssertLessThan(fourthMonth, firstMonth, "the same calories buy less loss as the body gets lighter")
        XCTAssertTrue(points.allSatisfy { $0.weightKg > 25 && $0.weightKg.isFinite })
    }

    func testMostOfTheWeightLostIsFatWhenTrainingAndProteinAreThere() {
        var lifter = losing
        lifter.trainingStyle = .strength
        lifter.trainingDaysPerWeek = 4
        XCTAssertGreaterThan(NutritionMath.fatLossShare(lifter), NutritionMath.fatLossShare(losing))
        let points = NutritionMath.projection(for: lifter, calorieTarget: 2000, weeks: 26)
        let start = points.first!, end = points.last!
        XCTAssertLessThan(end.bodyFatPercent!, start.bodyFatPercent!)
        let leanLost = start.leanMassKg! - end.leanMassKg!
        let totalLost = start.weightKg - end.weightKg
        XCTAssertLessThan(leanLost / totalLost, 0.15, "at most a small share of the loss should be lean mass")
    }

    func testMaintenanceHoldsSteady() {
        var steady = losing
        steady.goal = .maintain
        let target = NutritionMath.plan(for: steady).calories
        let points = NutritionMath.projection(for: steady, calorieTarget: target, weeks: 26)
        XCTAssertEqual(points.last!.weightKg, 95, accuracy: 1.5)
    }

    func testTheHonestGoalDateIsLaterThanTheNaiveOne() {
        let target = 74.0
        let naiveWeeks = NutritionMath.weeksToGoal(losing, targetKg: target)!
        let naiveDate = Calendar.current.date(byAdding: .day, value: Int(naiveWeeks * 7), to: Date())!
        let real = NutritionMath.projectedGoalDate(for: losing, calorieTarget: 2000, targetKg: target)
        XCTAssertNotNil(real)
        XCTAssertGreaterThan(real!, naiveDate, "the forecast must not promise a straight line")
    }

    func testAdaptationIsBoundedAtATenth() {
        XCTAssertEqual(NutritionMath.adaptation(startWeightKg: 100, currentWeightKg: 100), 1, accuracy: 0.001)
        XCTAssertEqual(NutritionMath.adaptation(startWeightKg: 100, currentWeightKg: 95), 0.97, accuracy: 0.001)
        XCTAssertEqual(NutritionMath.adaptation(startWeightKg: 100, currentWeightKg: 50), 0.90, accuracy: 0.001)
    }
}

final class TrendEngineTests: XCTestCase {
    private func samples(_ values: [Double], from start: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> [TrendEngine.Sample] {
        values.enumerated().map { TrendEngine.Sample(date: Calendar.current.date(byAdding: .day, value: $0.offset, to: start)!, weightKg: $0.element) }
    }

    func testTheTrendIgnoresASingleNoisyDay() {
        var values = Array(repeating: 80.0, count: 20)
        values[10] = 82.5                                   // a salty dinner, not two and a half kilos of fat
        let points = TrendEngine.trend(samples(values))
        XCTAssertEqual(points.count, 20)
        XCTAssertLessThan(points[10].trend, 80.4, "one spike should barely move the line")
        XCTAssertEqual(points.last!.trend, 80, accuracy: 0.15)
    }

    func testTheTrendFollowsARealChange() {
        let values = (0..<40).map { 90.0 - Double($0) * 0.1 }   // a steady 0.7 kg a week
        let points = TrendEngine.trend(samples(values))
        XCTAssertEqual(TrendEngine.weeklyRate(points, overDays: 21)!, -0.7, accuracy: 0.05)
        XCTAssertEqual(points.last!.trend, values.last!, accuracy: 0.3, "carrying the slope should remove the lag a moving average would have")
        XCTAssertEqual(points.last!.slopePerDay, -0.1, accuracy: 0.02)
    }

    func testGapsInWeighingDoNotDistortTheLine() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let sparse = [0, 9, 18, 27].map {
            TrendEngine.Sample(date: cal.date(byAdding: .day, value: $0, to: start)!, weightKg: 85 - Double($0) * 0.1)
        }
        let points = TrendEngine.trend(sparse)
        XCTAssertEqual(points.count, 28, "every day between the first and last reading gets a value")
        XCTAssertEqual(points.last!.trend, 82.3, accuracy: 0.8)
    }

    func testDeviationSeparatesWaterFromFat() {
        var values = Array(repeating: 80.0, count: 15)
        values[14] = 81.5
        let points = TrendEngine.trend(samples(values))
        XCTAssertEqual(TrendEngine.deviation(points)!, 1.5, accuracy: 0.3)
    }

    func testMeasuredBurnUsesTheTrendNotTheRawScale() {
        // 28 days at 2,000 calories, trend down 2 kg. That is 2,000 + 2 x 7700 / 28 = 2,550.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let weights = (0..<29).map { TrendEngine.Sample(date: cal.date(byAdding: .day, value: $0, to: start)!, weightKg: 80 - Double($0) * (2.0 / 28)) }
        let points = TrendEngine.trend(weights, timeConstant: 1)   // follow the readings closely for the test
        let intake = (0..<29).map { (date: cal.date(byAdding: .day, value: $0, to: start)!, calories: Double?(2000)) }
        let estimate = TrendEngine.adaptiveTDEE(intakeByDay: intake, trend: points, predictedTDEE: 2400)!
        XCTAssertEqual(estimate.tdee, 2550, accuracy: 40)
        XCTAssertEqual(estimate.loggedDays, 29)
        XCTAssertGreaterThan(estimate.confidence, 0.9)
        XCTAssertTrue(estimate.isTrustworthy)
        XCTAssertEqual(Double(estimate.blended), 2550, accuracy: 60, "a full log should barely be pulled toward the prediction")
    }

    func testPatchyLoggingIsPulledTowardThePrediction() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let weights = (0..<29).map { TrendEngine.Sample(date: cal.date(byAdding: .day, value: $0, to: start)!, weightKg: 80 - Double($0) * (2.0 / 28)) }
        let points = TrendEngine.trend(weights, timeConstant: 1)
        let intake = (0..<29).map { day in
            (date: cal.date(byAdding: .day, value: day, to: start)!, calories: day % 2 == 0 ? Double?(2000) : nil)
        }
        let estimate = TrendEngine.adaptiveTDEE(intakeByDay: intake, trend: points, predictedTDEE: 2200)!
        XCTAssertLessThan(estimate.confidence, 0.8)
        XCTAssertLessThan(estimate.blended, estimate.tdee, "half a log is half an answer")
    }

    func testImpossibleNumbersAreRejectedRatherThanShown() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let weights = (0..<29).map { TrendEngine.Sample(date: cal.date(byAdding: .day, value: $0, to: start)!, weightKg: 80 - Double($0) * 0.3) }
        let points = TrendEngine.trend(weights, timeConstant: 1)
        let intake = (0..<29).map { (date: cal.date(byAdding: .day, value: $0, to: start)!, calories: Double?(1200)) }
        XCTAssertNil(TrendEngine.adaptiveTDEE(intakeByDay: intake, trend: points, predictedTDEE: 2400),
                     "losing 0.3 kg a day on 1,200 calories means the log is wrong, not the metabolism")
    }

    func testTooFewDaysGivesNothing() {
        let points = TrendEngine.trend(samples(Array(repeating: 80.0, count: 8)))
        let intake = (0..<8).map { (date: Calendar.current.date(byAdding: .day, value: $0, to: Date(timeIntervalSince1970: 1_700_000_000))!, calories: Double?(2000)) }
        XCTAssertNil(TrendEngine.adaptiveTDEE(intakeByDay: intake, trend: points, predictedTDEE: 2400))
    }

    func testVerdicts() {
        XCTAssertEqual(TrendEngine.verdict(rate: -0.5, goal: .lose, targetRateKg: 0.5), .onTrack(rateKg: -0.5))
        XCTAssertEqual(TrendEngine.verdict(rate: -0.1, goal: .lose, targetRateKg: 0.5), .slower(rateKg: -0.1))
        XCTAssertEqual(TrendEngine.verdict(rate: -1.2, goal: .lose, targetRateKg: 0.5), .faster(rateKg: -1.2))
        XCTAssertEqual(TrendEngine.verdict(rate: 0.01, goal: .lose, targetRateKg: 0.5), .stalled)
        XCTAssertEqual(TrendEngine.verdict(rate: 0.4, goal: .lose, targetRateKg: 0.5), .wrongWay(rateKg: 0.4))
        XCTAssertEqual(TrendEngine.verdict(rate: nil, goal: .lose, targetRateKg: 0.5), .notEnoughData)
        XCTAssertEqual(TrendEngine.verdict(rate: 0.1, goal: .maintain, targetRateKg: 0), .onTrack(rateKg: 0.1))
        XCTAssertFalse(TrendEngine.verdict(rate: -0.5, goal: .lose, targetRateKg: 0.5).isProblem)
        XCTAssertTrue(TrendEngine.verdict(rate: 0.4, goal: .lose, targetRateKg: 0.5).isProblem)
    }

    func testAdviceReadsInTheUsersUnits() {
        let metric = TrendEngine.advice(.onTrack(rateKg: -0.5), goal: .lose, units: .metric)!
        XCTAssertTrue(metric.detail.contains("0.50 kg"))
        let imperial = TrendEngine.advice(.onTrack(rateKg: -0.5), goal: .lose, units: .imperial)!
        XCTAssertTrue(imperial.detail.contains("1.10 lb"))
    }

    func testAdherence() {
        let cal = Calendar.current
        let days = (0..<14).map { (date: cal.date(byAdding: .day, value: $0, to: Date())!, calories: $0 % 2 == 0 ? Double?(1800) : nil) }
        XCTAssertEqual(TrendEngine.adherence(intakeByDay: days), 0.5, accuracy: 0.01)
        XCTAssertEqual(TrendEngine.adherence(intakeByDay: []), 0)
    }
}

final class ProfileTests: XCTestCase {
    func testFocusAreasAndObstaclesSurviveARoundTrip() {
        let p = Profile()
        p.focusAreas = [.chest, .midsection]
        p.obstacles = [.cravings, .lateNight]
        p.avoids = ["dairy", "shellfish"]
        XCTAssertEqual(p.focusAreas, [.chest, .midsection])
        XCTAssertEqual(p.obstacles, [.cravings, .lateNight])
        XCTAssertEqual(p.avoids, ["dairy", "shellfish"])
        p.focusAreas = []
        XCTAssertTrue(p.focusAreas.isEmpty)
    }

    func testAgeComesFromTheBirthDateWhenThereIsOne() {
        let p = Profile()
        p.birthYear = 1990
        XCTAssertEqual(p.age, Calendar.current.component(.year, from: Date()) - 1990)
        p.birthDate = Calendar.current.date(byAdding: .year, value: -28, to: Date())
        XCTAssertEqual(p.age, 28)
    }

    func testOnlyTrustworthyBodyFatReachesTheCalorieMath() {
        let p = Profile()
        p.sex = .male; p.heightCm = 180; p.weightKg = 80
        XCTAssertEqual(p.bodyFat?.source, .estimated)
        XCTAssertNil(p.trustedBodyFat, "a BMI guess must not drive the calorie target")
        XCTAssertNil(p.inputs.bodyFatPercent)
        p.neckCm = 38; p.waistCm = 85
        XCTAssertEqual(p.bodyFat?.source, .tape)
        XCTAssertNotNil(p.trustedBodyFat)
        XCTAssertNotNil(p.inputs.bodyFatPercent)
    }

    func testRecalculateWritesEveryTarget() {
        let p = Profile()
        p.goal = .lose
        p.dailyActivity = .desk
        p.recalculateTargets()
        XCTAssertGreaterThan(p.calorieTarget, 1000)
        XCTAssertGreaterThan(p.proteinTarget, 50)
        XCTAssertGreaterThan(p.fiberTarget, 10)
        XCTAssertGreaterThan(p.waterMl, 1000)
        XCTAssertFalse(p.targetsEditedByUser)
    }
}

final class GoalChoiceTests: XCTestCase {
    func testTickingBothLoseFatAndBuildMuscleIsARecomposition() {
        XCTAssertEqual(Goal.from([.loseFat, .buildMuscle]), .recomp)
        XCTAssertEqual(Goal.from([.loseFat]), .lose)
        XCTAssertEqual(Goal.from([.buildMuscle]), .gain)
        XCTAssertEqual(Goal.from([.maintain]), .maintain)
    }

    func testNothingTickedIsNotAnAnswerYet() {
        XCTAssertNil(Goal.from([]))
        XCTAssertNil(Goal.from(Goal.toggling(.loseFat, in: [.loseFat])))
    }

    func testMaintainClearsTheOthersAndTheOthersClearMaintain() {
        var chosen = Goal.toggling(.maintain, in: [.loseFat, .buildMuscle])
        XCTAssertEqual(chosen, [.maintain])
        chosen = Goal.toggling(.buildMuscle, in: chosen)
        XCTAssertEqual(chosen, [.buildMuscle])
        XCTAssertEqual(Goal.from(chosen), .gain)
    }

    func testTwoTicksCanLiveTogetherWhenNeitherIsMaintain() {
        let chosen = Goal.toggling(.buildMuscle, in: Goal.toggling(.loseFat, in: []))
        XCTAssertEqual(chosen, [.loseFat, .buildMuscle])
        XCTAssertEqual(Goal.from(chosen), .recomp)
    }

    func testEveryGoalSurvivesARoundTripThroughTheTicks() {
        for goal in Goal.allCases {
            XCTAssertEqual(Goal.from(goal.choices), goal, "\(goal.rawValue) did not come back")
        }
    }

    func testTheStoredRawValuesAreUntouched() {
        // SwiftData reads these strings off disk, so the picker may change but they may not.
        XCTAssertEqual(Goal.allCases.map(\.rawValue), ["lose", "maintain", "gain", "recomp"])
    }
}

final class OnboardingFlowTests: XCTestCase {
    func testThePlanIsReachedInEightScreens() {
        // Working it out is a pause, not a question, so it is not one of the eight.
        let asked = OnboardingView.Step.essentials.filter { $0 != .generating }
        XCTAssertEqual(asked.count, 8)
        XCTAssertEqual(asked.first, .welcome)
        XCTAssertEqual(asked[1], .goal, "the goal frames every question after it")
        XCTAssertEqual(asked.last, .plan)
        XCTAssertFalse(OnboardingView.Step.essentials.contains(.trainingStyle),
                       "nothing optional belongs in the run that has to be finished")

        // Holding steady drops the two screens that only a moving target needs.
        let holding = asked.filter { $0 != .targetWeight && $0 != .pace }
        XCTAssertEqual(holding.count, 6)
    }

    func testEveryOptionalRunEndsAndNoneOverlap() {
        let steps = OnboardingView.chunks.flatMap(\.steps)
        XCTAssertEqual(Set(steps).count, steps.count, "a question belongs to one run only")
        for chunk in OnboardingView.chunks {
            XCTAssertGreaterThan(chunk.steps.count, 1, "\(chunk.title) has an intro and nothing else")
            XCTAssertFalse(chunk.steps.contains(.plan), "the plan is where a run ends, not part of it")
            XCTAssertFalse(chunk.promise.isEmpty, "\(chunk.title) does not say what it buys")
        }
    }

    func testSkippingEveryOptionalQuestionLeavesTheTargetWhereItWas() {
        // Exactly what phase one asks for, and not one answer more.
        let p = Profile()
        p.sex = .male
        p.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())
        p.heightCm = 180
        p.weightKg = 80
        p.dailyActivity = .desk
        p.goal = .lose
        p.targetWeightKg = 74
        p.paceKgPerWeek = 0.5

        // The defaults the skipped questions leave behind, written out rather than read back off
        // the profile, so moving any of them fails here rather than quietly moving someone's target.
        XCTAssertEqual(p.trainingStyle, .none)
        XCTAssertEqual(p.trainingDaysPerWeek, 0)
        XCTAssertEqual(p.trainingMinutes, 45)
        XCTAssertEqual(p.experience, .none)
        XCTAssertEqual(p.diet, .balanced)
        XCTAssertEqual(p.mealPattern, .three)
        XCTAssertEqual(p.cycling, .even)
        XCTAssertEqual(p.drinksPerWeek, 0)
        XCTAssertNil(p.neckCm)
        XCTAssertNil(p.waistCm)
        XCTAssertNil(p.targetBodyFat)
        XCTAssertNil(p.trustedBodyFat)
        XCTAssertTrue(p.focusAreas.isEmpty)
        XCTAssertTrue(p.obstacles.isEmpty)
        XCTAssertTrue(p.avoids.isEmpty)

        let expected = NutritionMath.Inputs(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                            activity: .light, goal: .lose, paceKgPerWeek: 0.5,
                                            bodyFatPercent: nil, dailyActivity: .desk,
                                            trainingDaysPerWeek: 0, trainingMinutes: 45,
                                            trainingStyle: .none, experience: .none, diet: .balanced)
        XCTAssertEqual(p.inputs, expected)

        let plan = NutritionMath.plan(for: expected)
        p.recalculateTargets()
        XCTAssertEqual(p.calorieTarget, plan.calories)
        XCTAssertEqual(p.proteinTarget, plan.protein)
        XCTAssertEqual(p.carbTarget, plan.carbs)
        XCTAssertEqual(p.fatTarget, plan.fat)
        XCTAssertEqual(p.fiberTarget, plan.fiber)
        XCTAssertEqual(p.waterMl, plan.waterMl)
        XCTAssertEqual(plan.method, "Mifflin-St Jeor")
    }

    func testTheTrainingLoadQuestionNamesWhatWasPicked() {
        XCTAssertTrue(TrainingStyle.strength.loadQuestion.contains("lifting"))
        XCTAssertTrue(TrainingStyle.cardio.loadQuestion.contains("running"))
        XCTAssertTrue(TrainingStyle.yoga.loadQuestion.contains("yoga"))
        for style in TrainingStyle.allCases {
            XCTAssertTrue(style.loadQuestion.hasSuffix("?"), "\(style.rawValue) does not ask anything")
        }
    }
}

final class MeasurementTests: XCTestCase {
    func testTapeMeasurementFillsInBodyFat() {
        let m = BodyMeasurement()
        m.neckCm = 38; m.waistCm = 85
        XCTAssertTrue(!m.isEmpty)
        m.refreshBodyFat(sex: .male, heightCm: 180, fallbackWeightKg: 80)
        XCTAssertEqual(m.bodyFatPercent!, 16.1, accuracy: 0.2)
        XCTAssertEqual(m.bodyFatSource, .tape)
        XCTAssertEqual(m.weightKg, 80)
    }

    func testAnEnteredNumberIsNeverOverwritten() {
        let m = BodyMeasurement()
        m.bodyFatPercent = 11
        m.bodyFatSource = .entered
        m.neckCm = 38; m.waistCm = 85
        m.refreshBodyFat(sex: .male, heightCm: 180, fallbackWeightKg: 80)
        XCTAssertEqual(m.bodyFatPercent, 11)
    }

    func testFieldAccessByKey() {
        let m = BodyMeasurement()
        for field in BodyMeasurement.fields {
            m.setValue(42, for: field.key)
            XCTAssertEqual(m.value(for: field.key), 42, "\(field.key) did not round trip")
        }
        XCTAssertNil(m.value(for: "nonsense"))
        XCTAssertFalse(m.isEmpty)
    }
}

final class FocusGuidanceTests: XCTestCase {
    func testEveryAreaHasUsableGuidance() {
        for area in BodyArea.allCases {
            for goal in AreaGoal.allCases {
                let plan = FocusGuidance.plan(for: area, goal: goal, sex: .male)
                XCTAssertFalse(plan.headline.isEmpty)
                XCTAssertFalse(plan.truth.isEmpty)
                XCTAssertFalse(plan.training.isEmpty)
                XCTAssertFalse(plan.nutrition.isEmpty)
                XCTAssertFalse(plan.measure.isEmpty)
            }
        }
    }

    func testChestAdviceWarnsMenAboutGlandularTissue() {
        let male = FocusGuidance.plan(for: .chest, goal: .leaner, sex: .male)
        XCTAssertNotNil(male.caution)
        XCTAssertTrue(male.caution!.lowercased().contains("doctor"))
        XCTAssertNil(FocusGuidance.plan(for: .chest, goal: .leaner, sex: .female).caution)
    }

    func testNothingPromisesSpotReduction() {
        for area in BodyArea.allCases {
            let text = FocusGuidance.plan(for: area, goal: .leaner, sex: .female)
            XCTAssertFalse(text.truth.isEmpty)
        }
        XCTAssertTrue(FocusGuidance.spotReductionNote.contains("cannot"))
    }
}

final class MealTests: XCTestCase {
    func testTotalsFollowItems() {
        let meal = MealEntry(name: "Test", source: .manual)
        let rice = MealItem(name: "Rice", quantity: 1, unit: "cup", gramsPerUnit: 158,
                            base: Nutrients(calories: 205, protein: 4, carbs: 45, fat: 0.4, fiber: 0.6, sugar: 0, sodium: 2))
        let chicken = MealItem(name: "Chicken", quantity: 150, unit: "g", gramsPerUnit: 1,
                               base: Nutrients(calories: 1.65, protein: 0.31, carbs: 0, fat: 0.036, fiber: 0, sugar: 0, sodium: 0.74))
        meal.items = [rice, chicken]
        meal.recalculate()
        XCTAssertEqual(meal.calories, 205 + 247.5, accuracy: 0.01)
        XCTAssertEqual(meal.protein, 4 + 46.5, accuracy: 0.01)
        rice.quantity = 2
        meal.recalculate()
        XCTAssertEqual(meal.calories, 410 + 247.5, accuracy: 0.01)
    }

    /// The model reports totals for the portion eaten. The app stores per unit values, so a 1.5 cup
    /// serving of 308 kcal has to come back as 205 kcal a cup, and scaling it must return the total.
    func testAnalyzerParsingUsesTotals() throws {
        let json = """
        {"m":"Chicken and rice","i":[{"n":"Rice","q":1.5,"u":"cup","g":237,
        "c":307.5,"p":6,"cb":67.5,"f":0.6,"fb":0.9,"s":0,"so":3,"cf":0.8}],
        "cf":0.7,"h":7,"t":"Plain."}
        """
        let meal = try FoodAnalyzer.parse(Data(json.utf8), source: .photo)
        XCTAssertEqual(meal.name, "Chicken and rice")
        XCTAssertEqual(meal.totals.calories, 307.5, accuracy: 0.01)
        XCTAssertEqual(meal.items[0].base.calories, 205, accuracy: 0.01)
        XCTAssertEqual(meal.items[0].gramsPerUnit ?? 0, 158, accuracy: 0.01)
        XCTAssertEqual(meal.items[0].grams ?? 0, 237, accuracy: 0.01)
        XCTAssertEqual(meal.healthScore, 7)
        XCTAssertEqual(meal.notes, "Plain.")
    }

    /// A quantity of zero must not divide by zero or wipe the numbers out.
    func testAnalyzerParsingSurvivesZeroQuantity() throws {
        let json = """
        {"m":"Snack","i":[{"n":"Bar","q":0,"u":"piece","g":40,
        "c":180,"p":5,"cb":22,"f":8,"fb":2,"s":12,"so":90,"cf":0.6}],
        "cf":0.6,"h":5,"t":"One bar."}
        """
        let meal = try FoodAnalyzer.parse(Data(json.utf8), source: .photo)
        XCTAssertEqual(meal.items[0].quantity, 1)
        XCTAssertEqual(meal.totals.calories, 180, accuracy: 0.01)
    }

    /// The failure this guard exists for: the model reads a 100 g portion as quantity 100 and hands
    /// back the whole portion's calories in every field, giving 16,500 kcal of chicken breast.
    func testImplausibleCaloriesAreRepaired() {
        let runaway = Nutrients(calories: 16500, protein: 31, carbs: 0, fat: 3.6,
                                fiber: 0, sugar: 0, sodium: 74)
        let fixed = FoodAnalyzer.plausible(runaway, grams: 100)
        XCTAssertFalse(fixed.trusted)
        // 31 g protein and 3.6 g fat is about 156 kcal, which is what a chicken breast actually is.
        XCTAssertEqual(fixed.nutrients.calories, 31 * 4 + 3.6 * 9, accuracy: 0.01)
        XCTAssertLessThanOrEqual(fixed.nutrients.calories / 100, FoodAnalyzer.maxKcalPerGram)
    }

    func testPlausibleLeavesHonestFoodAlone() {
        // Olive oil is the densest real food there is, at 9 kcal a gram, and must survive untouched.
        let oil = Nutrients(calories: 119, protein: 0, carbs: 0, fat: 13.5,
                            fiber: 0, sugar: 0, sodium: 0)
        let checked = FoodAnalyzer.plausible(oil, grams: 13.5)
        XCTAssertTrue(checked.trusted)
        XCTAssertEqual(checked.nutrients.calories, 119, accuracy: 0.01)
    }

    func testPlausibleFallsBackWhenMacrosAreAlsoImpossible() {
        // Nothing to cross-check against, so it clamps to the densest food that could weigh this.
        let nonsense = Nutrients(calories: 9000, protein: 0, carbs: 0, fat: 0,
                                 fiber: 0, sugar: 0, sodium: 0)
        let checked = FoodAnalyzer.plausible(nonsense, grams: 50)
        XCTAssertFalse(checked.trusted)
        XCTAssertEqual(checked.nutrients.calories, 50 * FoodAnalyzer.maxKcalPerGram, accuracy: 0.01)
    }

    /// Every key in the request schema has to be one `parse` reads back, or a scan is paid for and
    /// then thrown away. This catches the two drifting apart.
    func testAnalyzerSchemaMatchesParser() throws {
        let properties = FoodAnalyzer.mealSchema["properties"] as! [String: Any]
        XCTAssertEqual(Set(properties.keys), ["m", "i", "cf", "h", "t"])
        let items = properties["i"] as! [String: Any]
        let item = items["items"] as! [String: Any]
        let itemKeys = Set((item["properties"] as! [String: Any]).keys)
        XCTAssertEqual(itemKeys, ["n", "q", "u", "g", "c", "p", "cb", "f", "fb", "s", "so", "cf"])
        // Required lists must not name a key the schema does not declare.
        XCTAssertTrue(Set(item["required"] as! [String]).isSubset(of: itemKeys))
        XCTAssertTrue(Set(FoodAnalyzer.mealSchema["required"] as! [String]).isSubset(of: Set(properties.keys)))
    }

    func testUsageCostMatchesPublishedRates() {
        // 1,353 input and 984 output tokens on Flash-Lite, the measured shape of a large meal.
        let dollars = AIUsage.cost(model: "gemini-3.5-flash-lite", input: 1353, output: 984)
        XCTAssertEqual(dollars, 1353 * 0.30 / 1e6 + 984 * 2.50 / 1e6, accuracy: 1e-9)
        // An unknown model must never be counted as free.
        XCTAssertGreaterThan(AIUsage.cost(model: "gemini-9-unknown", input: 1000, output: 1000), 0)
    }

    func testOpenFoodFactsParsing() {
        let p: [String: Any] = [
            "code": "123", "product_name": "Oat bar", "brands": "Acme, Other", "serving_size": "40 g", "serving_quantity": 40,
            "nutriments": ["energy-kcal_100g": 400, "proteins_100g": 10.0, "carbohydrates_100g": 60, "fat_100g": 12, "fiber_100g": 5, "sugars_100g": 20, "sodium_100g": 0.2],
        ]
        let product = OpenFoodFacts.parse(p)!
        XCTAssertEqual(product.brand, "Acme")
        XCTAssertEqual(product.perServing!.calories, 160, accuracy: 0.01)
        XCTAssertEqual(product.per100g.sodium, 200, accuracy: 0.01)
    }

    func testStreakAndRollover() {
        let cal = Calendar.current
        let today = Date()
        let m1 = MealEntry(name: "a", date: today, source: .manual); m1.calories = 1500
        let m2 = MealEntry(name: "b", date: cal.date(byAdding: .day, value: -1, to: today)!, source: .manual); m2.calories = 1500
        let m3 = MealEntry(name: "c", date: cal.date(byAdding: .day, value: -3, to: today)!, source: .manual)
        XCTAssertEqual(DayStats.streak(meals: [m1, m2, m3], today: today), 2)
        XCTAssertEqual(DayStats.rollover(target: 2000, meals: [m1, m2], today: today), 250)
        XCTAssertEqual(DayStats.rollover(target: 1600, meals: [m1, m2], today: today), 100)
    }
}

final class GeminiSchemaTests: XCTestCase {
    func testSchemaConversion() throws {
        let out = GeminiClient.geminiSchema(FoodAnalyzer.mealSchema)
        XCTAssertEqual(out["type"] as? String, "OBJECT")
        XCTAssertNil(out["additionalProperties"])
        let props = try XCTUnwrap(out["properties"] as? [String: Any])
        // "i" is the component array. The keys are one or two letters because every one of them is
        // billed as output on every scan.
        let items = try XCTUnwrap(props["i"] as? [String: Any])
        XCTAssertEqual(items["type"] as? String, "ARRAY")
        let item = try XCTUnwrap(items["items"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "OBJECT")
        let itemProps = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertEqual((itemProps["q"] as? [String: Any])?["type"] as? String, "NUMBER")
        XCTAssertEqual((itemProps["n"] as? [String: Any])?["type"] as? String, "STRING")
        XCTAssertEqual((item["required"] as? [String])?.count, 12)
    }
}

final class GeminiModelTests: XCTestCase {
    func testRetiredModelIsGone() {
        let retired = "This model models/gemini-2.5-flash is no longer available to new users. Please update your code to use models/gemini-3.6-flash"
        XCTAssertEqual(GeminiClient.verdict(status: 404, message: retired), .gone)
        XCTAssertEqual(GeminiClient.verdict(status: 400, message: "models/x is not found for API version v1beta"), .gone)
        XCTAssertEqual(GeminiClient.verdict(status: 429, message: "Quota exceeded for metric, limit: 0, model: gemini-x"), .gone)
    }

    func testOverloadAndQuotaAreBusyNotFatal() {
        XCTAssertEqual(GeminiClient.verdict(status: 503, message: "This model is currently experiencing high demand."), .busy)
        XCTAssertEqual(GeminiClient.verdict(status: 429, message: "You exceeded your current quota, please check your plan"), .busy)
        XCTAssertEqual(GeminiClient.verdict(status: 500, message: "Internal error"), .busy)
    }

    func testBadKeyAndBadRequestAreFatal() {
        XCTAssertEqual(GeminiClient.verdict(status: 401, message: "API key not valid"), .fatal)
        XCTAssertEqual(GeminiClient.verdict(status: 400, message: "Invalid JSON payload"), .fatal)
        XCTAssertEqual(GeminiClient.verdict(status: 403, message: "Permission denied"), .fatal)
    }

    func testCandidatesPutRememberedFirstWithoutRepeats() {
        let remembered = GeminiClient.preferred.last!
        let list = GeminiClient.candidates(remembered: remembered)
        XCTAssertEqual(list.first, remembered)
        XCTAssertEqual(list.count, GeminiClient.preferred.count)
        XCTAssertEqual(GeminiClient.candidates(remembered: nil), GeminiClient.preferred)
        XCTAssertEqual(GeminiClient.candidates(remembered: "gemini-9-flash").first, "gemini-9-flash")
    }

    /// The fallback chain is Lite only on purpose. A full size Flash model bills output at up to
    /// thirteen times the Lite rate, so one busy minute used to turn into a bill nobody asked for.
    func testFallbackChainIsLiteOnly() {
        for model in GeminiClient.preferred {
            XCTAssertTrue(model.contains("lite"), "\(model) is not a Lite model")
        }
        XCTAssertEqual(GeminiClient.preferred.first, "gemini-3.1-flash-lite",
                       "the cheapest model that benchmarked well should be tried first")
    }

    func testDiscoveryKeepsGeneralFlashNewestFirst() {
        let ranked = GeminiClient.rankDiscovered([
            (name: "models/gemini-3.5-flash", methods: ["generateContent"]),
            (name: "models/gemini-3.8-flash", methods: ["generateContent", "countTokens"]),
            (name: "models/gemini-3.8-flash-lite", methods: ["generateContent"]),
            (name: "models/gemini-3.8-flash-image", methods: ["generateContent"]),
            (name: "models/gemini-3.8-pro", methods: ["generateContent"]),
            (name: "models/gemini-4.0-flash", methods: ["embedContent"]),
            (name: "models/text-embedding-004", methods: ["embedContent"]),
        ])
        XCTAssertEqual(ranked, ["gemini-3.8-flash-lite", "gemini-3.8-flash", "gemini-3.5-flash"])
    }

    func testThinkingIsSetToMinimal() {
        XCTAssertEqual(GeminiClient.thinkingConfig["thinkingLevel"] as? String, "minimal")   // Lite rejects a zero budget
        XCTAssertEqual(GeminiClient.thinkingConfig.count, 1)   // the API rejects a budget and a level together
    }

    func testAny400IsWorthOneTryWithoutTheSetting() {
        XCTAssertTrue(GeminiClient.isThinkingRejected(status: 400, message: "Request contains an invalid argument."))
        XCTAssertTrue(GeminiClient.isThinkingRejected(status: 400, message: "This model only works in thinking mode."))
        XCTAssertFalse(GeminiClient.isThinkingRejected(status: 404, message: "not found"))
        XCTAssertFalse(GeminiClient.isThinkingRejected(status: 429, message: "quota"))
    }

    func testLiteIsTriedFirst() {
        XCTAssertTrue(GeminiClient.preferred[0].contains("lite"))
        // The full size models used to sit at the end of this list. They were removed once measuring
        // showed 3.5 Flash bills output at $9 per million against Lite's $1.50, so a busy Lite quietly
        // cost thirteen times more. When every Lite is busy the scan now fails and can be retried.
        XCTAssertFalse(GeminiClient.preferred.contains("gemini-3.5-flash"))
        XCTAssertFalse(GeminiClient.preferred.contains("gemini-3.6-flash"))
    }
}

/// Stands in for Google's servers so the fallback loop can be exercised end to end.
final class StubGemini: URLProtocol {
    static var log: [(model: String, hinted: Bool)] = []
    static var handler: ((_ model: String, _ hinted: Bool) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "generativelanguage.googleapis.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let path = request.url?.path ?? ""
        let model = path.contains("/models/") ? (path.components(separatedBy: "/models/").last?.components(separatedBy: ":").first ?? "") : ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
        }
        let hinted = String(decoding: body, as: UTF8.self).contains("thinkingConfig")
        StubGemini.log.append((model, hinted))
        let (status, text) = StubGemini.handler?(model, hinted) ?? (500, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class GeminiFallbackTests: XCTestCase {
    let first = GeminiClient.preferred[0], second = GeminiClient.preferred[1]
    let ok = #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{\"ok\":true}"}]}}]}"#
    func error(_ m: String) -> String { #"{"error":{"message":"\#(m)"}}"# }
    let schema: [String: Any] = ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"]]

    override func setUp() {
        URLProtocol.registerClass(StubGemini.self)
        StubGemini.log = []
        let d = UserDefaults.standard
        d.dictionaryRepresentation().keys.filter { $0.hasPrefix("gemini.") }.forEach(d.removeObject)
    }
    override func tearDown() { URLProtocol.unregisterClass(StubGemini.self); setUp(); URLProtocol.unregisterClass(StubGemini.self) }

    func testRetiredModelThenRejectedHintThenSuccess() async throws {
        StubGemini.handler = { [self] model, hinted in
            if model == first { return (404, error("This model is no longer available to new users.")) }
            if hinted { return (400, error("This model only works in thinking mode.")) }
            return (200, ok)
        }
        var client = GeminiClient(); client.keyOverride = "test"
        let data = try await client.structured(system: "s", content: .init(text: "ping"), schema: schema, maxTokens: 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"ok":true}"#)
        XCTAssertEqual(StubGemini.log.map(\.model), [first, second, second])
        XCTAssertEqual(StubGemini.log.map(\.hinted), [true, true, false])
        XCTAssertEqual(GeminiClient.rememberedModel, second)

        // The next scan goes straight to the working model and skips the hint it learned is refused.
        StubGemini.log = []
        _ = try await client.structured(system: "s", content: .init(text: "ping"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.count, 1)
        XCTAssertEqual(StubGemini.log[0].model, second)
        XCTAssertFalse(StubGemini.log[0].hinted)
    }

    func testRealBadRequestStopsAfterOneRetryAndKeepsTheHint() async {
        StubGemini.handler = { [self] _, _ in (400, error("Request contains an invalid argument.")) }
        var client = GeminiClient(); client.keyOverride = "test"
        do { _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200); XCTFail("should throw") }
        catch AIError.http(let code, _) { XCTAssertEqual(code, 400) } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(StubGemini.log.map(\.hinted), [true, false], "one try with the setting, one without, then stop")
        XCTAssertFalse(UserDefaults.standard.dictionaryRepresentation().keys.contains { $0.hasPrefix("gemini.noThinkingHint") }, "the setting was not the problem, so keep using it")
    }

    func testBareInvalidArgumentFromTheHintIsRecovered() async throws {
        StubGemini.handler = { [self] _, hinted in hinted ? (400, error("Request contains an invalid argument.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.hinted), [true, false])
        XCTAssertEqual(GeminiClient.rememberedModel, first)
    }

    func testBadKeyStopsImmediately() async {
        StubGemini.handler = { [self] _, _ in (400, error("API key not valid. Please pass a valid API key.")) }
        var client = GeminiClient(); client.keyOverride = "bad"
        do { _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200); XCTFail("should throw") }
        catch AIError.http(let code, _) { XCTAssertEqual(code, 401) } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(StubGemini.log.count, 1)
    }

    func testCutOffAnswerRetriesWithMoreRoom() async throws {
        var calls = 0
        StubGemini.handler = { [self] _, _ in
            calls += 1
            return calls == 1 ? (200, #"{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"{\"o"}]}}]}"#) : (200, ok)
        }
        var client = GeminiClient(); client.keyOverride = "test"
        let data = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"ok":true}"#)
        XCTAssertEqual(calls, 2)
    }

    func testBusyModelUsesTheNextOneButKeepsThePreference() async throws {
        GeminiClient.rememberedModel = first
        StubGemini.handler = { [self] model, _ in model == first ? (503, error("This model is currently experiencing high demand.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.model), [first, second])
        XCTAssertEqual(GeminiClient.rememberedModel, first)
    }

    func testBusyModelIsSkippedOnTheNextScan() async throws {
        StubGemini.handler = { [self] model, _ in model == first ? (429, error("You exceeded your current quota. Please retry in 40.5s.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.model), [first, second])
        StubGemini.log = []
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.model), [second], "the busy model should not be asked again so soon")
        XCTAssertTrue(GeminiClient.isCoolingDown(first))
        XCTAssertFalse(GeminiClient.isCoolingDown(first, now: Date().addingTimeInterval(41)))
    }

    func testCooldownLengths() {
        XCTAssertEqual(GeminiClient.cooldown(status: 429, message: "Quota exceeded. Please retry in 34.2s."), 34.2, accuracy: 0.01)
        XCTAssertEqual(GeminiClient.cooldown(status: 429, message: "Please retry in 2s."), 15)
        XCTAssertEqual(GeminiClient.cooldown(status: 429, message: "You exceeded your current quota"), 120)
        XCTAssertEqual(GeminiClient.cooldown(status: 503, message: "This model is currently experiencing high demand."), 45)
    }

    /// The exact text Google sends for a used up daily allowance. It also says "retry in 41s", which must be ignored.
    func testDailyQuotaWaitsForThePacificResetNotFortyOneSeconds() {
        let daily = "You exceeded your current quota. * Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20, model: gemini-3.6-flash Please retry in 41.945671687s. [GenerateRequestsPerDayPerProjectPerModel-FreeTier]"
        XCTAssertEqual(GeminiClient.verdict(status: 429, message: daily), .busy, "limit: 20 is a used up allowance, not a missing model")
        var pacific = Calendar(identifier: .gregorian); pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let sixPM = pacific.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 18))!
        XCTAssertEqual(GeminiClient.cooldown(status: 429, message: daily, now: sixPM), 6 * 3600, accuracy: 1)
        XCTAssertEqual(GeminiClient.verdict(status: 429, message: "Quota exceeded, limit: 0, model: gemini-x"), .gone)
    }

    func testCoolingDownFavoriteIsNotReplacedForGood() async throws {
        StubGemini.handler = { [self] model, _ in model == first ? (503, error("This model is currently experiencing high demand.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)   // 3.6 busy, latest answers
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)   // 3.6 cooling, latest answers first try
        XCTAssertNil(GeminiClient.rememberedModel, "a model that only won because the best one was resting must not become the favorite")
        XCTAssertEqual(GeminiClient.candidates(remembered: GeminiClient.rememberedModel, now: Date().addingTimeInterval(60)).first, first)
    }

    func testEverythingBusyGivesUpAfterThreeModels() async {
        StubGemini.handler = { [self] _, _ in (429, error("You exceeded your current quota, please check your plan and billing details.")) }
        var client = GeminiClient(); client.keyOverride = "test"
        do { _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200); XCTFail("should throw") }
        catch let e as AIError { XCTAssertTrue(e.localizedDescription.contains("free limit")) } catch { XCTFail("wrong error") }
        XCTAssertEqual(StubGemini.log.count, 3)
    }

    func testEveryModelGoneFallsBackToTheAccountList() async throws {
        StubGemini.handler = { [self] model, _ in
            if model == "gemini-4.2-flash" { return (200, ok) }
            if model.isEmpty { return (200, #"{"models":[{"name":"models/gemini-4.2-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-4.2-flash-lite","supportedGenerationMethods":["generateContent"]}]}"#) }
            return (404, error("models/\(model) is not found for API version v1beta"))
        }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(GeminiClient.rememberedModel, "gemini-4.2-flash")
    }
}

/// Talks to the real service. Skipped unless a key is supplied:
/// TEST_RUNNER_GEMINI_KEY=... [TEST_RUNNER_GEMINI_IMAGE=/path/to/meal.jpg] xcodebuild test ...
final class GeminiLiveTests: XCTestCase {
    func testRealScanThroughTheAppClient() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["GEMINI_KEY"], !key.isEmpty else { throw XCTSkip("no GEMINI_KEY supplied") }
        let d = UserDefaults.standard
        d.dictionaryRepresentation().keys.filter { $0.hasPrefix("gemini.") }.forEach(d.removeObject)
        let image = env["GEMINI_IMAGE"].flatMap { UIImage(contentsOfFile: $0) }
        var client = GeminiClient(); client.keyOverride = key
        let started = Date()
        let data = try await client.structured(system: FoodAnalyzer.system,
                                               content: .init(text: "Estimate the nutrition of this meal: one cup of shelled edamame.", image: image),
                                               schema: FoodAnalyzer.mealSchema, maxTokens: 4000)
        let secondsFirst = Date().timeIntervalSince(started)
        if let image, let jpeg = AIClient.downscaled(image).jpegData(compressionQuality: 0.82) { print("LIVE upload bytes=\(jpeg.count)") }
        for n in 2...3 {
            let t = Date()
            _ = try await client.structured(system: FoodAnalyzer.system, content: .init(text: "Estimate the nutrition of this meal: one cup of shelled edamame.", image: image), schema: FoodAnalyzer.mealSchema, maxTokens: 4000)
            print("LIVE photo call \(n) seconds=\(String(format: "%.1f", Date().timeIntervalSince(t))) thought=\(GeminiClient.lastThoughtTokens)")
        }
        let thoughtFirst = GeminiClient.lastThoughtTokens
        let hintRefused = d.dictionaryRepresentation().keys.contains { $0.hasPrefix("gemini.noThinkingHint") }
        let again = Date()
        _ = try await client.structured(system: FoodAnalyzer.system, content: .init(text: "Estimate the nutrition of this meal: two scrambled eggs with a slice of buttered toast.", image: nil), schema: FoodAnalyzer.mealSchema, maxTokens: 4000)
        print("LIVE second call (text only) seconds=\(String(format: "%.1f", Date().timeIntervalSince(again))) thought=\(GeminiClient.lastThoughtTokens) hintRefused=\(hintRefused)")
        XCTAssertEqual(thoughtFirst, 0, "thinking should be off")
        let meal = try FoodAnalyzer.parse(data, source: .photo)
        print("LIVE model=\(GeminiClient.rememberedModel ?? "fallback") seconds=\(String(format: "%.1f", secondsFirst)) thought=\(thoughtFirst) image=\(image != nil) meal=\(meal.name) kcal=\(Int(meal.totals.calories)) protein=\(Int(meal.totals.protein))")
        XCTAssertFalse(meal.items.isEmpty)
        XCTAssertGreaterThan(meal.totals.calories, 100)
        XCTAssertLessThan(meal.totals.calories, 320)
    }
}

final class ImagePrepTests: XCTestCase {
    private func image(points: CGFloat, scale: CGFloat) -> UIImage {
        let f = UIGraphicsImageRendererFormat.default(); f.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: points, height: points * 0.75), format: f).image { c in
            UIColor.systemGreen.setFill(); c.fill(CGRect(x: 0, y: 0, width: points, height: points))
        }
    }
    private func pixels(_ i: UIImage) -> CGFloat { max(i.size.width, i.size.height) * i.scale }

    func testLargePhotoIsCappedAt1280Pixels() {
        XCTAssertEqual(pixels(AIClient.downscaled(image(points: 4032, scale: 1))), 1280, accuracy: 1)
    }
    func testHighScaleImageIsMeasuredInPixels() {
        XCTAssertEqual(pixels(AIClient.downscaled(image(points: 1000, scale: 3))), 1280, accuracy: 1)
    }
    func testSmallImageIsLeftAlone() {
        XCTAssertEqual(pixels(AIClient.downscaled(image(points: 800, scale: 1))), 800, accuracy: 1)
    }
}

final class PortionScalingTests: XCTestCase {
    private func meal() -> AnalyzedMeal {
        AnalyzedMeal(name: "Test",
                     items: [
                        AnalyzedMeal.Item(name: "Rice", quantity: 1.5, unit: "cup", gramsPerUnit: 158,
                                          base: Nutrients(calories: 205, protein: 4, carbs: 45, fat: 0.4, fiber: 0.6, sugar: 0, sodium: 2),
                                          confidence: 0.5),
                        AnalyzedMeal.Item(name: "Chicken", quantity: 200, unit: "g", gramsPerUnit: 1,
                                          base: Nutrients(calories: 1.65, protein: 0.31, carbs: 0, fat: 0.036, fiber: 0, sugar: 0, sodium: 0.74),
                                          confidence: 0.8),
                     ],
                     notes: "", healthScore: 7, confidence: 0.55, source: .photo)
    }

    func testScalingEveryItemMovesTheTotalByTheSameFactor() {
        var m = meal()
        let before = m.totals.calories
        for index in m.items.indices {
            m.items[index].quantity = (m.items[index].quantity * 0.5 * 100).rounded() / 100
        }
        XCTAssertEqual(m.totals.calories, before * 0.5, accuracy: 0.5)
        XCTAssertEqual(m.items[0].quantity, 0.75, accuracy: 0.001)
        XCTAssertEqual(m.items[1].quantity, 100, accuracy: 0.001)
    }

    func testEveryOfferedScaleIsSensible() {
        let factors = ResultEditorView.scales.map(\.factor)
        XCTAssertEqual(factors.count, Set(factors).count, "no duplicate scales")
        XCTAssertTrue(factors.allSatisfy { $0 >= 0.5 && $0 <= 2 }, "nothing that would make the meal nonsense")
        XCTAssertTrue(factors.contains(0.5) && factors.contains(2), "halving and doubling are what people reach for")
        XCTAssertEqual(factors, factors.sorted(), "smallest first so the row reads left to right")
    }
}

final class SugarAndSodiumLimitTests: XCTestCase {

    /// 10 percent of energy at 4 calories a gram is calories divided by 40, so the two rules meet
    /// at 1,440 calories for men and 1,000 for women. Either side of that the stricter one has to
    /// be the one showing.
    func testTheTwoSugarRulesCrossOverWhereTheArithmeticSaysTheyDo() {
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 1440, sex: .male), 36)
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 1200, sex: .male), 30, "under the crossover the energy rule binds")
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 1600, sex: .male), 36, "over it the flat figure binds")

        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 1000, sex: .female), 25)
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 800, sex: .female), 20)
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 1200, sex: .female), 25,
                       "10 percent of 1,200 is 30 g, and the flat figure has to win or a small eater gets more than a moderate one")
    }

    func testAppetiteNeverBuysMoreSugar() {
        for calories in stride(from: 1500.0, through: 5000.0, by: 250) {
            XCTAssertEqual(NutritionMath.addedSugarLimit(calories: calories, sex: .male), 36)
            XCTAssertEqual(NutritionMath.addedSugarLimit(calories: calories, sex: .female), 25)
        }
    }

    func testTheSugarLimitOnlyEverFallsAsCaloriesFall() {
        for sex in Sex.allCases {
            var previous = 0
            for calories in stride(from: 400.0, through: 5000.0, by: 50) {
                let limit = NutritionMath.addedSugarLimit(calories: calories, sex: sex)
                XCTAssertGreaterThanOrEqual(limit, previous, "\(sex.rawValue) dipped at \(calories) calories")
                previous = limit
            }
        }
    }

    func testAMissingOrNonsenseCalorieFigureFallsBackToTheFlatLimit() {
        // A hand edited target can be anything. None of these may produce a limit of zero, which
        // the Today screen would read as already over.
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: 0, sex: .female), 25)
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: -500, sex: .male), 36)
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: .nan, sex: .male), 36)
        XCTAssertEqual(NutritionMath.addedSugarLimit(calories: .infinity, sex: .female), 25)
    }

    func testSodiumIsOneFigureForEveryone() {
        XCTAssertEqual(NutritionMath.sodiumLimit(), 2300)
    }

    func testBothLimitsSurviveRecalculating() {
        let p = Profile()
        p.sex = .female
        p.goal = .lose
        p.dailyActivity = .desk
        p.recalculateTargets()
        XCTAssertEqual(p.sugarLimit, p.plan.sugarLimit, "the stored limit has to be the one the math just worked out")
        XCTAssertEqual(p.sugarLimit, 25, "a woman on any target the app will set sits on the flat figure")
        XCTAssertEqual(p.sodiumLimit, 2300)

        p.sex = .male
        p.goal = .gain
        p.recalculateTargets()
        XCTAssertEqual(p.sugarLimit, 36, "a man in a surplus is well over the crossover")
        XCTAssertEqual(p.sodiumLimit, 2300)
    }

    func testAProfileFromBeforeTheLimitsExistedReadsBackTheDefaults() {
        // SwiftData fills a column added later from the property default, so an untouched profile
        // has to carry real numbers rather than zero.
        let old = Profile()
        XCTAssertEqual(old.sugarLimit, 36)
        XCTAssertEqual(old.sodiumLimit, 2300)
    }

    func testThePlanCarriesTheLimitsSoEveryScreenAgrees() {
        let i = NutritionMath.Inputs(sex: .female, age: 30, heightCm: 165, weightKg: 60,
                                     activity: .light, goal: .maintain, paceKgPerWeek: 0)
        let plan = NutritionMath.plan(for: i)
        XCTAssertEqual(plan.sugarLimit, 25)
        XCTAssertEqual(plan.sodiumLimit, 2300)
    }

    func testTheSugarRowSaysWhatItIsActuallyMeasuring() {
        let note = NutritionMath.totalVersusAddedSugarNote
        XCTAssertTrue(note.contains("added sugar"))
        XCTAssertTrue(note.contains("total sugar"))
        XCTAssertFalse(note.contains("\u{2014}"), "house style, no em dashes")
    }
}

final class NutrientBreakdownTests: XCTestCase {
    private func meal(_ name: String, at hour: Int, on day: Date,
                      items: [(String, Nutrients)]) -> MealEntry {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let entry = MealEntry(name: name, date: date, source: .manual)
        entry.items = items.enumerated().map { index, item in
            MealItem(name: item.0, quantity: 1, unit: "serving", gramsPerUnit: nil, base: item.1, order: index)
        }
        entry.recalculate()
        return entry
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private func lunchAndDinner() -> [MealEntry] {
        [meal("Lunch", at: 12, on: today, items: [
            ("Chicken breast", Nutrients(calories: 260, protein: 52, carbs: 0, fat: 6, fiber: 0, sugar: 0, sodium: 130)),
            ("Rice", Nutrients(calories: 205, protein: 4, carbs: 45, fat: 1, fiber: 1, sugar: 0, sodium: 2)),
         ]),
         meal("Dinner", at: 19, on: today, items: [
            ("Salmon", Nutrients(calories: 350, protein: 34, carbs: 0, fat: 22, fiber: 0, sugar: 0, sodium: 300)),
         ])]
    }

    /// The whole point of the screen: the chicken, not the lunch it was part of.
    func testRankingIsByItemAndBiggestFirst() {
        let rows = NutrientContribution.ranked(.protein, meals: lunchAndDinner(), day: today)
        XCTAssertEqual(rows.map(\.name), ["Chicken breast", "Salmon", "Rice"])
        XCTAssertEqual(rows[0].amount, 52, accuracy: 0.001)
        XCTAssertEqual(rows[0].mealName, "Lunch", "the sitting is still worth naming under the item")
    }

    /// Rice has no fat worth showing and salmon has no fiber, so neither should pad the list.
    func testItemsWithNoneOfTheNutrientAreLeftOut() {
        let rows = NutrientContribution.ranked(.fiber, meals: lunchAndDinner(), day: today)
        XCTAssertEqual(rows.map(\.name), ["Rice"])
    }

    /// The ranked amounts have to add up to the number on Today, or the sheet contradicts the tile.
    func testTheRowsAddUpToTheDayTotal() {
        let meals = lunchAndDinner()
        for nutrient in [BreakdownNutrient.protein, .carbs, .fat, .sodium] {
            let summed = NutrientContribution.ranked(nutrient, meals: meals, day: today).reduce(0) { $0 + $1.amount }
            let total = nutrient.amount(in: DayStats.totals(on: today, meals: meals))
            XCTAssertEqual(summed, total, accuracy: 0.001, "\(nutrient.title) disagrees with the day")
        }
    }

    func testOtherDaysAreNotCounted() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        var meals = lunchAndDinner()
        meals.append(meal("Yesterday's lunch", at: 13, on: yesterday, items: [
            ("Steak", Nutrients(calories: 500, protein: 60, carbs: 0, fat: 28, fiber: 0, sugar: 0, sodium: 200)),
        ]))
        let rows = NutrientContribution.ranked(.protein, meals: meals, day: today)
        XCTAssertFalse(rows.contains { $0.name == "Steak" })
        XCTAssertEqual(rows.count, 3)
    }

    /// An entry saved before items existed still has totals, and dropping it would quietly lose
    /// protein the day was actually credited with.
    func testAMealWithNoItemsStandsInForItself() {
        let bare = MealEntry(name: "Old entry", date: today, source: .manual)
        bare.totals = Nutrients(calories: 300, protein: 25, carbs: 10, fat: 12, fiber: 2, sugar: 3, sodium: 400)
        let rows = NutrientContribution.ranked(.protein, meals: [bare], day: today)
        XCTAssertEqual(rows.map(\.name), ["Old entry"])
        XCTAssertEqual(rows[0].amount, 25, accuracy: 0.001)
    }

    /// Equal contributions have to land in a fixed order or the list reshuffles on every redraw.
    func testTiesFallBackToTheEarlierMeal() {
        let meals = [meal("Dinner", at: 19, on: today, items: [("Tofu", Nutrients(protein: 20))]),
                     meal("Breakfast", at: 8, on: today, items: [("Eggs", Nutrients(protein: 20))])]
        XCTAssertEqual(NutrientContribution.ranked(.protein, meals: meals, day: today).map(\.name), ["Eggs", "Tofu"])
    }

    /// Going over on sugar or sodium is the bad outcome, and going over on the other four is not,
    /// so the sheet must not read them the same way.
    func testOnlySugarAndSodiumAreLimits() {
        XCTAssertEqual(BreakdownNutrient.allCases.filter(\.isLimit), [.sugar, .sodium])
        XCTAssertEqual(BreakdownNutrient.sodium.unit, "mg")
        XCTAssertTrue(BreakdownNutrient.allCases.filter { $0 != .sodium }.allSatisfy { $0.unit == "g" })
    }

    func testEachNutrientReadsItsOwnTarget() {
        let profile = Profile()
        profile.proteinTarget = 180
        profile.carbTarget = 200
        profile.fatTarget = 60
        profile.fiberTarget = 30
        profile.sugarLimit = 25
        profile.sodiumLimit = 2300
        XCTAssertEqual(BreakdownNutrient.allCases.map { $0.goal(for: profile) },
                       [180, 200, 60, 30, 25, 2300])
    }

    /// Sugar is the one row that would mislead without a sentence beside it.
    func testOnlySugarCarriesACaveat() {
        XCTAssertEqual(BreakdownNutrient.sugar.caveat, NutritionMath.totalVersusAddedSugarNote)
        XCTAssertTrue(BreakdownNutrient.allCases.filter { $0 != .sugar }.allSatisfy { $0.caveat == nil })
    }
}

// MARK: - Reading a wearable

/// The arithmetic behind the Apple Health feature, which is the half that can be checked without a
/// band on a wrist. Every test here is about not counting the same calories twice.
final class WearableSignalsTests: XCTestCase {

    /// A middling adult: 1,700 resting, 2,500 all in, 300 of that predicted from the MET table.
    private let prediction = HealthSignals.Prediction(bmr: 1700, tdee: 2500, trainingKcalPerDay: 300)

    private func days(_ count: Int, active: Double, basal: Double?) -> [HealthSignals.DayEnergy] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (1...count).map { offset in
            HealthSignals.DayEnergy(date: cal.date(byAdding: .day, value: -offset, to: start) ?? start,
                                    activeKcal: active, basalKcal: basal)
        }
    }

    private func sessions(_ count: Int, kcal: Int?, minutes: Int = 45,
                          source: HealthSignals.Source = .whoop) -> [HealthSignals.Workout] {
        let cal = Calendar.current
        return (1...count).map { offset in
            let start = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return HealthSignals.Workout(id: UUID(), date: start,
                                         end: start.addingTimeInterval(Double(minutes) * 60),
                                         kind: "Running", minutes: minutes, kcal: kcal, source: source)
        }
    }

    // MARK: Who wrote it

    func testWhoopIsRecognizedByBundleAndByName() {
        XCTAssertEqual(HealthSignals.classify(bundleIdentifier: "com.whoop.iphone",
                                              productType: "iPhone14,2", name: "WHOOP"), .whoop)
        XCTAssertEqual(HealthSignals.classify(bundleIdentifier: "com.example.bridge",
                                              productType: nil, name: "Whoop Sync"), .whoop)
    }

    /// Apple writes its own samples under a per device bundle identifier, so only the hardware
    /// model separates a watch from the phone it syncs to.
    func testOnlyTheProductTypeTellsAWatchFromAPhone() {
        let bundle = "com.apple.health.A1B2C3D4"
        XCTAssertEqual(HealthSignals.classify(bundleIdentifier: bundle, productType: "Watch6,2",
                                              name: "Sam's Apple Watch"), .appleWatch)
        XCTAssertEqual(HealthSignals.classify(bundleIdentifier: bundle, productType: "iPhone16,1",
                                              name: "Sam's iPhone"), .iPhone)
        XCTAssertEqual(HealthSignals.classify(bundleIdentifier: bundle, productType: nil,
                                              name: "Sam's iPhone"), .other("Sam's iPhone"))
    }

    func testTheBandOutranksTheWatchAndBothOutrankThePhone() {
        let order = [HealthSignals.Source.whoop, .appleWatch, .other("Strava"), .iPhone]
        XCTAssertEqual(order.map(\.rank), order.map(\.rank).sorted(), "worn sources first, phone last")
        XCTAssertEqual(order.map(\.rank).count, Set(order.map(\.rank)).count, "no ties to break")
    }

    // MARK: A whole day off the device

    func testAMeasuredDayIsMovementPlusRestingAndNothingElse() {
        let burn = HealthSignals.measuredBurn(days: days(28, active: 700, basal: 1700),
                                              workouts: [], source: .appleWatch,
                                              prediction: prediction)
        XCTAssertEqual(burn?.basis, .wholeDay)
        XCTAssertEqual(burn?.tdee, 2400, "700 moving and 1,700 resting")
        XCTAssertNotEqual(burn?.tdee, 4100, "the resting burn must not be added a second time")
    }

    /// The one that would inflate a target every day if it were wrong.
    func testAPredictedRestingBurnIsNeverAddedToAMeasuredOne() {
        let burn = HealthSignals.measuredBurn(days: days(28, active: 700, basal: 1700),
                                              workouts: [], source: .appleWatch,
                                              prediction: prediction)
        XCTAssertEqual(burn?.restingKcal, 1700, "the measured figure, not the measured plus the equation")
        XCTAssertEqual((burn?.activeKcal ?? 0) + (burn?.restingKcal ?? 0), burn?.tdee)
    }

    /// A source that puts the whole day into the field meant for movement alone.
    func testAWholeDayTotalWrittenAsActiveEnergyIsRefused() {
        let burn = HealthSignals.measuredBurn(days: days(28, active: 2400, basal: 1700),
                                              workouts: [], source: .whoop,
                                              prediction: prediction)
        XCTAssertNil(burn, "movement beating the entire resting burn every day is a mislabeled total")
    }

    func testDaysTheDeviceWasNotWornDoNotCount() {
        // A fortnight of real wear and a fortnight of resting burn far below what a body needs.
        let worn = days(14, active: 700, basal: 1700)
        let off = days(14, active: 20, basal: 300)
        let burn = HealthSignals.measuredBurn(days: worn + off, workouts: [], source: .appleWatch,
                                              prediction: prediction)
        XCTAssertEqual(burn?.days, 14)
        XCTAssertEqual(burn?.tdee, 2400)
    }

    func testTooFewDaysIsNoAnswerAtAll() {
        XCTAssertNil(HealthSignals.measuredBurn(days: days(5, active: 700, basal: 1700),
                                                workouts: [], source: .appleWatch, prediction: prediction))
    }

    /// The simulator, and every phone without a wearable beside it.
    func testNothingInHealthProducesNothing() {
        XCTAssertNil(HealthSignals.measuredBurn(days: [], workouts: [], source: .iPhone,
                                                prediction: prediction))
        XCTAssertEqual(HealthSignals.prior(measured: nil, predictedTDEE: 2500), 2500,
                       "no reading leaves the prediction exactly where it was")
    }

    // MARK: Sessions only, which is what a Whoop writes

    /// Without a resting burn in Health, an active energy figure could cover the whole day or only
    /// the sessions in it, and those differ by every calorie of everyday movement. The sessions are
    /// unambiguous, so they are what gets used.
    func testActiveEnergyWithNoRestingBurnFallsBackToTheSessions() {
        let burn = HealthSignals.measuredBurn(days: days(28, active: 700, basal: nil),
                                              workouts: sessions(8, kcal: 600),
                                              source: .whoop, prediction: prediction)
        XCTAssertEqual(burn?.basis, .workoutsOnly)
        XCTAssertEqual(burn?.activeKcal, 171, "4,800 kcal of sessions spread over 28 days")
        XCTAssertNotEqual(burn?.activeKcal, 700, "an ambiguous daily figure is not used")
    }

    /// Measured training replaces the MET table estimate. Adding it would count training twice.
    func testMeasuredTrainingReplacesThePredictedTrainingRatherThanAddingToIt() {
        let burn = HealthSignals.measuredBurn(days: [], workouts: sessions(12, kcal: 500),
                                              source: .whoop, prediction: prediction)
        XCTAssertEqual(burn?.restingKcal, 2200, "the 2,500 day with its predicted 300 of training taken out")
        XCTAssertEqual(burn?.tdee, 2414)
        XCTAssertNotEqual(burn?.tdee, 2714, "2,500 plus the sessions would count training twice")
    }

    func testSessionsWithNoEnergyFigureAreNotPricedAtZero() {
        XCTAssertNil(HealthSignals.measuredBurn(days: [], workouts: sessions(12, kcal: nil),
                                                source: .whoop, prediction: prediction),
                     "sessions Plate cannot price would drag the average down and cut the target")
    }

    func testOneOrTwoSessionsIsNotAPicture() {
        XCTAssertNil(HealthSignals.measuredBurn(days: [], workouts: sessions(2, kcal: 500),
                                                source: .whoop, prediction: prediction))
    }

    func testTheMeasuredFigureIsHeldNearTheEquation() {
        // Sessions large enough that believing them whole would move the target a long way.
        let burn = HealthSignals.measuredBurn(days: [], workouts: sessions(20, kcal: 2500, minutes: 120),
                                              source: .whoop, prediction: prediction)
        XCTAssertNotNil(burn)
        XCTAssertLessThanOrEqual(Double(burn?.blended ?? 0), 2500 * 1.5)
        XCTAssertLessThan(burn?.blended ?? 0, burn?.tdee ?? 0, "confidence pulls it back toward the equation")
    }

    // MARK: Two devices, one day

    func testARunLoggedTwiceCountsOnce() {
        let start = Date()
        let watch = HealthSignals.Workout(id: UUID(), date: start, end: start.addingTimeInterval(3600),
                                          kind: "Running", minutes: 60, kcal: 600, source: .appleWatch)
        let band = HealthSignals.Workout(id: UUID(), date: start.addingTimeInterval(120),
                                         end: start.addingTimeInterval(3500),
                                         kind: "Running", minutes: 56, kcal: 640, source: .whoop)
        let kept = HealthSignals.deduplicate([watch, band])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.source, .whoop, "the source Plate trusts most survives")
    }

    func testSessionsThatDoNotOverlapAreBothKept() {
        let start = Date()
        let morning = HealthSignals.Workout(id: UUID(), date: start, end: start.addingTimeInterval(3600),
                                            kind: "Running", minutes: 60, kcal: 600, source: .whoop)
        let evening = HealthSignals.Workout(id: UUID(), date: start.addingTimeInterval(36000),
                                            end: start.addingTimeInterval(39600),
                                            kind: "Cycling", minutes: 60, kcal: 500, source: .whoop)
        XCTAssertEqual(HealthSignals.deduplicate([morning, evening]).count, 2)
    }

    /// Whoop writes a sample per sleep stage and a watch writes its own beside it.
    func testOverlappingSleepIsCountedOnce() {
        let start = Date()
        let first = (start: start, end: start.addingTimeInterval(3600))
        let overlapping = (start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400))
        XCTAssertEqual(HealthSignals.unionMinutes([first, overlapping]), 90, accuracy: 0.01)
        XCTAssertEqual(HealthSignals.unionMinutes([first, first]), 60, accuracy: 0.01)
    }

    func testAGapBetweenSleepSamplesIsNotCounted() {
        let start = Date()
        let first = (start: start, end: start.addingTimeInterval(3600))
        let later = (start: start.addingTimeInterval(7200), end: start.addingTimeInterval(10800))
        XCTAssertEqual(HealthSignals.unionMinutes([first, later]), 120, accuracy: 0.01)
        XCTAssertEqual(HealthSignals.unionMinutes([]), 0)
    }

    // MARK: The weekly picture

    func testAStrayAutoDetectedWalkIsNotASession() {
        let real = sessions(4, kcal: 500, minutes: 45)
        let strays = sessions(10, kcal: 20, minutes: 6)
        let week = HealthSignals.trainingWeek(real + strays, overDays: 28)
        XCTAssertEqual(week?.sessions, 1, "four sessions across four weeks")
        XCTAssertEqual(week?.averageMinutes, 45)
    }

    func testNoWorkoutsMeansNoWeeklyPicture() {
        XCTAssertNil(HealthSignals.trainingWeek([], overDays: 28))
        XCTAssertNil(HealthSignals.trainingWeek(sessions(3, kcal: 100, minutes: 5), overDays: 28))
    }
}

/// The target already contains a normal day's movement, so only the part of a measured day that
/// beats that assumption is new. Getting this wrong adds several hundred calories every day, and
/// with a watch closer to seven hundred, which is the difference between losing and gaining.
final class ExerciseCalorieTests: XCTestCase {
    private func inputs() -> NutritionMath.Inputs {
        var i = NutritionMath.Inputs(sex: .male, age: 27, heightCm: 180, weightKg: 84,
                                     activity: .light, goal: .lose, paceKgPerWeek: 0.5)
        i.dailyActivity = .desk
        i.trainingStyle = .strength
        i.trainingDaysPerWeek = 4
        i.trainingMinutes = 60
        return i
    }

    /// Everything above resting is already spoken for by the activity factor.
    private func extra(_ measured: Double, _ i: NutritionMath.Inputs) -> Double {
        max(0, measured - (NutritionMath.tdee(i) - NutritionMath.bmr(i)))
    }

    func testAnOrdinaryDayEarnsNothingExtra() {
        let i = inputs()
        let assumed = NutritionMath.tdee(i) - NutritionMath.bmr(i)
        XCTAssertEqual(extra(assumed, i), 0, accuracy: 0.01)
        // A quieter than usual day must never hand back calories either.
        XCTAssertEqual(extra(assumed * 0.5, i), 0, accuracy: 0.01)
    }

    func testOnlyTheSurplusIsAdded() {
        let i = inputs()
        let assumed = NutritionMath.tdee(i) - NutritionMath.bmr(i)
        XCTAssertEqual(extra(assumed + 300, i), 300, accuracy: 0.01)
    }

    /// The old behaviour added the whole measured figure. This pins the size of that mistake so
    /// nobody reintroduces it thinking it looks generous.
    func testTheOldBehaviourWouldHaveDoubleCounted() {
        let i = inputs()
        let measured = NutritionMath.tdee(i) - NutritionMath.bmr(i)
        XCTAssertGreaterThan(measured, 400, "an active day is worth hundreds of calories")
        XCTAssertEqual(extra(measured, i), 0, accuracy: 0.01)
    }
}

/// The bug this pins: Today showed 2,640 while the Ask tab said 2,390, and said 485 over when the
/// ring said 235 over. Both gaps were exactly 250, the rollover cap. Today used an adjusted target
/// and everything else quoted the stored baseline, so the app contradicted itself by however much
/// had rolled over. There is one function now and both screens must read it.
final class DayTargetTests: XCTestCase {
    private func profile(target: Int, rollover: Bool) -> Profile {
        let p = Profile()
        p.sex = .male
        p.heightCm = 180
        p.weightKg = 84
        p.calorieTarget = target
        p.rolloverCalories = rollover
        p.addExerciseCalories = false
        p.cycling = .even
        return p
    }

    private func meal(kcal: Double, on day: Date) -> MealEntry {
        let m = MealEntry(name: "Meal", date: day, source: .describe)
        m.items = [MealItem(name: "Food", quantity: 1, unit: "serving", gramsPerUnit: nil,
                            base: Nutrients(calories: kcal, protein: 0, carbs: 0, fat: 0,
                                            fiber: 0, sugar: 0, sodium: 0), confidence: 1)]
        m.recalculate()
        return m
    }

    func testRolloverIsInTheDayTargetNotJustTheRing() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let p = profile(target: 2390, rollover: true)
        // 2,000 eaten against 2,390 leaves 390, capped at 250.
        let target = DayStats.dayTarget(profile: p, meals: [meal(kcal: 2000, on: yesterday)], day: today)
        XCTAssertEqual(target.base, 2390)
        XCTAssertEqual(target.rollover, 250)
        XCTAssertEqual(target.total, 2640)
    }

    func testTheAdjustmentIsExplainable() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let p = profile(target: 2390, rollover: true)
        let target = DayStats.dayTarget(profile: p, meals: [meal(kcal: 2000, on: yesterday)], day: today)
        let labels = target.adjustments.map(\.label)
        XCTAssertEqual(labels, ["rolled over"], "a day that only rolled over should say only that")
        XCTAssertEqual(target.adjustments.first?.amount, 250)
    }

    func testRolloverOffMeansTheBaselineStands() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let p = profile(target: 2390, rollover: false)
        let target = DayStats.dayTarget(profile: p, meals: [meal(kcal: 2000, on: yesterday)], day: today)
        XCTAssertEqual(target.total, 2390)
        XCTAssertTrue(target.adjustments.isEmpty)
    }

    /// Earned calories are measured for today alone, so a day in the past must not collect them.
    func testEarnedCaloriesOnlyApplyToToday() {
        let p = profile(target: 2390, rollover: false)
        p.addExerciseCalories = true
        let past = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        XCTAssertEqual(DayStats.dayTarget(profile: p, meals: [], day: past, extraBurn: 300).earned, 0)
        XCTAssertEqual(DayStats.dayTarget(profile: p, meals: [], day: Date(), extraBurn: 300).earned, 300)
    }

    /// The brief the Ask tab is given has to carry the same number the ring shows.
    func testTheBriefQuotesTodaysAllowanceNotTheBaseline() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let p = profile(target: 2390, rollover: true)
        let meals = [meal(kcal: 2000, on: yesterday)]
        let text = Coach.brief(profile: p, meals: meals, weights: [], today: today).text
        XCTAssertTrue(text.contains("2640"), "the brief must quote today's allowance\n\(text)")
        XCTAssertTrue(text.contains("rolled over"), "and say why it differs from the baseline")
    }
}

/// Learning from corrections, and the lines it must not cross.
final class FoodCorrectionTests: XCTestCase {
    func testNormalizeCollapsesTheSameFood() {
        XCTAssertEqual(FoodCorrection.normalize("Chicken Breast "), "chicken breast")
        XCTAssertEqual(FoodCorrection.normalize("chicken  breast"), "chicken breast")
        XCTAssertEqual(FoodCorrection.normalize("Chicken-breast!"), "chickenbreast")
    }

    func testSmallNudgesTeachNothing() {
        // Someone rounding 200 to 210 is not telling the app anything about their plate.
        XCTAssertFalse(FoodCorrection.isWorthLearning(estimated: 200, corrected: 210))
        XCTAssertFalse(FoodCorrection.isWorthLearning(estimated: 200, corrected: 190))
    }

    func testARealCorrectionIsLearned() {
        XCTAssertTrue(FoodCorrection.isWorthLearning(estimated: 200, corrected: 400))
        XCTAssertTrue(FoodCorrection.isWorthLearning(estimated: 400, corrected: 200))
    }

    /// A typo or a mis-scaled entry must not become a permanent belief about someone's diet.
    func testImplausibleCorrectionsAreIgnored() {
        XCTAssertFalse(FoodCorrection.isWorthLearning(estimated: 200, corrected: 20000))
        XCTAssertFalse(FoodCorrection.isWorthLearning(estimated: 200, corrected: 1))
        XCTAssertFalse(FoodCorrection.isWorthLearning(estimated: 0, corrected: 300))
        XCTAssertFalse(FoodCorrection.isWorthLearning(estimated: 300, corrected: 0))
    }

    func testRepeatedCorrectionsConvergeOnTheUsualPortion() {
        let c = FoodCorrection(key: "chicken breast", displayName: "Chicken breast",
                               grams: 120, ratio: 1, calories: 200)
        for _ in 0..<6 { c.absorb(grams: 220, ratio: 1.8, calories: 360) }
        XCTAssertEqual(c.grams ?? 0, 220, accuracy: 2, "it should settle on the size actually eaten")
        XCTAssertEqual(c.count, 7)
    }

    /// One unusual day should move it, but not erase the habit behind it.
    func testOneOddDayDoesNotEraseTheHabit() {
        let c = FoodCorrection(key: "rice", displayName: "Rice", grams: 300, ratio: 1.5, calories: 400)
        for _ in 0..<5 { c.absorb(grams: 300, ratio: 1.5, calories: 400) }
        c.absorb(grams: 60, ratio: 0.3, calories: 80)
        XCTAssertGreaterThan(c.grams ?? 0, 100, "a single small day must not drag it all the way down")
    }

    func testPromptPrefersGramsOverAMultiplier() {
        let withGrams = FoodCorrection(key: "steak", displayName: "Steak", grams: 250, ratio: 2, calories: 600)
        XCTAssertTrue(withGrams.promptPhrase.contains("250 g"))
        let without = FoodCorrection(key: "soup", displayName: "Soup", grams: nil, ratio: 1.6, calories: 300)
        XCTAssertTrue(without.promptPhrase.contains("1.6"))
    }

    /// The prompt must tell the model that what it can see still wins. Learning someone's usual
    /// portion should not make it ignore a small plate in front of it.
    func testTheHintNeverOutranksThePhoto() {
        let profile = Profile()
        let c = FoodCorrection(key: "steak", displayName: "Steak", grams: 250, ratio: 2, calories: 600)
        let context = FoodAnalyzer.Context(profile: profile, corrections: [c])
        let line = context.promptLine
        XCTAssertTrue(line.contains("Steak"))
        XCTAssertTrue(line.lowercased().contains("contradicts it"),
                      "the photo has to be allowed to overrule a learned portion\n\(line)")
    }

    /// The bug this guards against, found against the live model before it shipped: an earlier
    /// wording made the list read as things the person eats, so a chicken salad came back with 300 g
    /// of rice in it and a bowl of rice came back with a chicken breast. A list of foods beside a
    /// meal is a strong suggestion to include them, so the refusal has to be explicit and has to come
    /// before anything else in the sentence.
    func testTheHintRefusesToBeReadAsIngredients() {
        let corrections = [
            FoodCorrection(key: "chicken breast", displayName: "Chicken breast", grams: 250, ratio: 2, calories: 400),
            FoodCorrection(key: "white rice", displayName: "White rice", grams: 300, ratio: 1.5, calories: 390),
        ]
        let line = FoodAnalyzer.Context(profile: Profile(), corrections: corrections).promptLine
        let lower = line.lowercased()
        XCTAssertTrue(lower.contains("not a list of what they ate"))
        XCTAssertTrue(lower.contains("never add a food"))
        XCTAssertTrue(lower.contains("they are not ingredients"))
        // The refusal has to land before the foods are named, or it is read as an afterthought.
        let refusal = try? XCTUnwrap(lower.range(of: "never add a food"))
        let firstFood = try? XCTUnwrap(lower.range(of: "chicken breast is usually"))
        if let refusal, let firstFood {
            XCTAssertLessThan(refusal.lowerBound, firstFood.lowerBound)
        }
    }

    /// Every phrase is billed on every scan, so the list has to stay short.
    func testOnlyTheMostCorrectedFoodsAreSent() {
        let many = (0..<30).map { i -> FoodCorrection in
            let c = FoodCorrection(key: "food\(i)", displayName: "Food \(i)",
                                   grams: 100, ratio: 1.5, calories: 200)
            c.count = i
            return c
        }
        let context = FoodAnalyzer.Context(profile: Profile(), corrections: many)
        XCTAssertEqual(context.learned.count, FoodAnalyzer.Context.learnedLimit)
        XCTAssertTrue(context.learned.first?.contains("Food 29") == true, "most corrected first")
    }

    /// A meal repeated from the log carries numbers the user already set, so editing it says
    /// nothing about how the model reads a plate. Source alone cannot tell: a repeat keeps the
    /// source of the meal it copied, so a repeated photo meal used to look like a fresh estimate.
    func testARepeatedMealIsNotAFreshEstimate() {
        let item = AnalyzedMeal.Item(name: "Rice", quantity: 1, unit: "cup", gramsPerUnit: 150,
                                     base: Nutrients(calories: 200, protein: 4, carbs: 45, fat: 0,
                                                     fiber: 1, sugar: 0, sodium: 2),
                                     confidence: 0.8)
        let fresh = AnalyzedMeal(name: "Rice", items: [item], notes: "", healthScore: 6,
                                 confidence: 0.8, source: .photo)
        XCTAssertTrue(fresh.fromEstimate, "a photo scan is an estimate and should teach")

        let repeated = AnalyzedMeal(name: "Rice", items: [item], notes: "", healthScore: 6,
                                    confidence: 0.8, source: .photo, fromEstimate: false)
        XCTAssertFalse(repeated.fromEstimate, "a repeat keeps its source but must not teach")
    }

    func testNoCorrectionsMeansNoExtraTokens() {
        let context = FoodAnalyzer.Context(profile: Profile(), corrections: [])
        XCTAssertFalse(context.promptLine.lowercased().contains("corrected portions"))
    }
}


/// The coach told its owner it did not know their height while the app showed it two screens away,
/// because the brief simply never carried it. These pin the contents so a fact the app displays
/// cannot silently go missing from what the coach is told.
final class CoachBriefTests: XCTestCase {
    private func profile() -> Profile {
        let p = Profile()
        p.sex = .male
        p.heightCm = 180
        p.weightKg = 84.2
        p.birthDate = Calendar.current.date(byAdding: .year, value: -27, to: Date())
        p.goal = .lose
        p.targetWeightKg = 77
        p.paceKgPerWeek = 0.5
        p.dailyActivity = .desk
        p.trainingStyle = .strength
        p.trainingDaysPerWeek = 4
        p.trainingMinutes = 60
        p.diet = .highProtein
        p.avoids = ["shellfish"]
        p.calorieTarget = 2390
        p.proteinTarget = 181
        p.onboarded = true
        return p
    }

    func testTheBriefCarriesTheBodyFactsTheAppDisplays() {
        let text = Coach.brief(profile: profile(), meals: [], weights: []).text
        XCTAssertTrue(text.contains("180"), "height is missing\n\(text)")
        XCTAssertTrue(text.contains("84"), "weight is missing")
        XCTAssertTrue(text.contains("27"), "age is missing")
        XCTAssertTrue(text.contains("77"), "target weight is missing")
    }

    func testTheBriefCarriesHowTheyLive() {
        let text = Coach.brief(profile: profile(), meals: [], weights: []).text.lowercased()
        XCTAssertTrue(text.contains("high protein"), "way of eating is missing")
        XCTAssertTrue(text.contains("shellfish"), "foods avoided are missing")
        XCTAssertTrue(text.contains("trains"), "training is missing")
    }

    /// A suggestion has to fit what is left, so the gap per macro has to be in the brief.
    func testTheBriefSpellsOutWhatIsLeftToday() {
        let text = Coach.brief(profile: profile(), meals: [], weights: []).text
        XCTAssertTrue(text.contains("2390"), "today's allowance is missing")
        XCTAssertTrue(text.lowercased().contains("nothing logged yet today"))
    }

    /// Foods someone avoids must be stated as a prohibition, not buried as a preference.
    func testAvoidedFoodsAreStatedAsAProhibition() {
        let text = Coach.brief(profile: profile(), meals: [], weights: []).text
        XCTAssertTrue(text.contains("never suggest"), "avoids must read as a rule\n\(text)")
    }
}

/// What the assistant is allowed to do, and what it is not. The complaint that started this was that
/// it refused to answer what should I eat next, which is the main thing anyone wants to ask it.
final class CoachScopeTests: XCTestCase {
    func testItIsToldToUseGeneralNutritionKnowledge() {
        let s = Coach.system.lowercased()
        XCTAssertTrue(s.contains("general knowledge about food"))
        XCTAssertFalse(s.contains("answer only from that brief"),
                       "answering only from the brief is what stopped it suggesting food")
    }

    func testItIsToldToAnswerWhatToEatNext() {
        XCTAssertTrue(Coach.system.lowercased().contains("what should i eat next"))
    }

    func testItStillRefusesWorkThatIsNotAboutFood() {
        let s = Coach.system.lowercased()
        XCTAssertTrue(s.contains("writing code"))
        XCTAssertTrue(s.contains("do not attempt it anyway"))
    }

    func testItStillRefusesToPractiseMedicine() {
        let s = Coach.system.lowercased()
        XCTAssertTrue(s.contains("not a doctor"))
        XCTAssertTrue(s.contains("eating disorder"))
    }

    func testSuggestionsLeadWithWhatToEatNext() {
        let list = Coach.suggestions(profile: Profile(), hasMeals: true)
        XCTAssertEqual(list.first, "What should I eat next?")
    }
}
