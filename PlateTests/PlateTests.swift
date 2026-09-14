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
