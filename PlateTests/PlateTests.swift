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

    func testAnalyzerParsing() throws {
        let json = """
        {"meal_name":"Chicken and rice","items":[{"name":"Rice","quantity":1.5,"unit":"cup","grams_per_unit":158,
        "calories_per_unit":205,"protein_g_per_unit":4,"carbs_g_per_unit":45,"fat_g_per_unit":0.4,"fiber_g_per_unit":0.6,
        "sugar_g_per_unit":0,"sodium_mg_per_unit":2,"confidence":0.8}],"confidence":0.7,"health_score":7,"notes":"Plain."}
        """
        let meal = try FoodAnalyzer.parse(Data(json.utf8), source: .photo)
        XCTAssertEqual(meal.name, "Chicken and rice")
        XCTAssertEqual(meal.totals.calories, 307.5, accuracy: 0.01)
        XCTAssertEqual(meal.items[0].grams ?? 0, 237, accuracy: 0.01)
        XCTAssertEqual(meal.healthScore, 7)
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
    func testSchemaConversion() {
        let out = GeminiClient.geminiSchema(FoodAnalyzer.mealSchema)
        XCTAssertEqual(out["type"] as? String, "OBJECT")
        XCTAssertNil(out["additionalProperties"])
        let props = out["properties"] as! [String: Any]
        let items = props["items"] as! [String: Any]
        XCTAssertEqual(items["type"] as? String, "ARRAY")
        let item = items["items"] as! [String: Any]
        XCTAssertEqual(item["type"] as? String, "OBJECT")
        XCTAssertEqual(((item["properties"] as! [String: Any])["quantity"] as! [String: Any])["type"] as? String, "NUMBER")
        XCTAssertEqual((item["required"] as! [String]).count, 12)
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
        let list = GeminiClient.candidates(remembered: "gemini-3.5-flash")
        XCTAssertEqual(list.first, "gemini-3.5-flash")
        XCTAssertEqual(list.count, GeminiClient.preferred.count)
        XCTAssertEqual(GeminiClient.candidates(remembered: nil), GeminiClient.preferred)
        XCTAssertEqual(GeminiClient.candidates(remembered: "gemini-9-flash").first, "gemini-9-flash")
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
        XCTAssertTrue(GeminiClient.preferred.contains("gemini-3.6-flash"), "full size backup for when Lite is busy")
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
