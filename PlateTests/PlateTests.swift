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
        XCTAssertEqual(ranked, ["gemini-3.8-flash", "gemini-3.5-flash"])
    }

    func testThinkingIsSwitchedOff() {
        XCTAssertEqual(GeminiClient.thinkingConfig["thinkingBudget"] as? Int, 0)
        XCTAssertEqual(GeminiClient.thinkingConfig.count, 1)   // the API rejects a budget and a level together
    }

    func testOnlyAThinkingComplaintDropsTheHint() {
        XCTAssertTrue(GeminiClient.isThinkingRejected(status: 400, message: "Unknown name \"thinkingLevel\" at generation_config.thinking_config"))
        XCTAssertFalse(GeminiClient.isThinkingRejected(status: 400, message: "Invalid JSON payload received"))
        XCTAssertFalse(GeminiClient.isThinkingRejected(status: 404, message: "thinking model not found"))
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
            if model == "gemini-3.6-flash" { return (404, error("This model models/gemini-3.6-flash is no longer available to new users.")) }
            if hinted { return (400, error("This model only works in thinking mode.")) }
            return (200, ok)
        }
        var client = GeminiClient(); client.keyOverride = "test"
        let data = try await client.structured(system: "s", content: .init(text: "ping"), schema: schema, maxTokens: 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"ok":true}"#)
        XCTAssertEqual(StubGemini.log.map(\.model), ["gemini-3.6-flash", "gemini-flash-latest", "gemini-flash-latest"])
        XCTAssertEqual(StubGemini.log.map(\.hinted), [true, true, false])
        XCTAssertEqual(GeminiClient.rememberedModel, "gemini-flash-latest")

        // The next scan goes straight to the working model and skips the hint it learned is refused.
        StubGemini.log = []
        _ = try await client.structured(system: "s", content: .init(text: "ping"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.count, 1)
        XCTAssertEqual(StubGemini.log[0].model, "gemini-flash-latest")
        XCTAssertFalse(StubGemini.log[0].hinted)
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
        GeminiClient.rememberedModel = "gemini-3.6-flash"
        StubGemini.handler = { [self] model, _ in model == "gemini-3.6-flash" ? (503, error("This model is currently experiencing high demand.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.model), ["gemini-3.6-flash", "gemini-flash-latest"])
        XCTAssertEqual(GeminiClient.rememberedModel, "gemini-3.6-flash")
    }

    func testBusyModelIsSkippedOnTheNextScan() async throws {
        StubGemini.handler = { [self] model, _ in model == "gemini-3.6-flash" ? (429, error("You exceeded your current quota. Please retry in 40.5s.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.model), ["gemini-3.6-flash", "gemini-flash-latest"])
        StubGemini.log = []
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)
        XCTAssertEqual(StubGemini.log.map(\.model), ["gemini-flash-latest"], "the busy model should not be asked again so soon")
        XCTAssertTrue(GeminiClient.isCoolingDown("gemini-3.6-flash"))
        XCTAssertFalse(GeminiClient.isCoolingDown("gemini-3.6-flash", now: Date().addingTimeInterval(41)))
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
        StubGemini.handler = { [self] model, _ in model == "gemini-3.6-flash" ? (503, error("This model is currently experiencing high demand.")) : (200, ok) }
        var client = GeminiClient(); client.keyOverride = "test"
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)   // 3.6 busy, latest answers
        _ = try await client.structured(system: "s", content: .init(text: "x"), schema: schema, maxTokens: 200)   // 3.6 cooling, latest answers first try
        XCTAssertNil(GeminiClient.rememberedModel, "a model that only won because the best one was resting must not become the favorite")
        XCTAssertEqual(GeminiClient.candidates(remembered: GeminiClient.rememberedModel, now: Date().addingTimeInterval(60)).first, "gemini-3.6-flash")
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
