import Foundation

/// Turns a noisy scale into something you can steer by.
///
/// Day to day weight is mostly water, food still in you, and salt. A single reading says almost
/// nothing. The smoothed trend line here is the same idea as the Hacker's Diet: each new reading
/// nudges the line a fraction of the way toward itself, so real change shows through and daily
/// noise does not. Every rate the app quotes is measured from this line, never from two raw
/// readings.
enum TrendEngine {

    struct Sample: Equatable {
        var date: Date
        var weightKg: Double
    }

    struct TrendPoint: Identifiable, Equatable {
        var id: Date { date }
        var date: Date
        var raw: Double?
        var trend: Double
        /// Kilograms a day the line is moving at this point.
        var slopePerDay: Double = 0
    }

    /// Days for the level to catch up to a step change. Ten is slow enough to ignore a salty dinner
    /// and fast enough to notice a real stall inside a fortnight.
    static let timeConstantDays = 10.0
    /// The slope is smoothed more heavily than the level, because a rate that jumps around is
    /// useless for deciding anything.
    static let slopeTimeConstantDays = 21.0

    /// Smoothed weight for every day between the first and last reading.
    ///
    /// This tracks a level and a slope rather than a level alone. A plain moving average always
    /// trails a steady gain or loss by about its own window, so someone losing half a kilo a week
    /// would see a line reading almost a kilo heavy for the whole diet. Carrying the slope removes
    /// that lag. The weighting is time aware, so a week long gap counts for more than a day and
    /// missing a few weigh ins does not bend the line.
    static func trend(_ samples: [Sample], timeConstant: Double = timeConstantDays) -> [TrendPoint] {
        let sorted = samples.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }
        let cal = Calendar.current

        // One reading a day, averaged when there are several.
        var byDay: [Date: [Double]] = [:]
        for s in sorted { byDay[cal.startOfDay(for: s.date), default: []].append(s.weightKg) }
        let days = byDay.keys.sorted()
        guard let start = days.first, let end = days.last else { return [] }
        let slopeConstant = max(timeConstant, slopeTimeConstantDays)

        var out: [TrendPoint] = []
        var level = byDay[start].map { $0.reduce(0, +) / Double($0.count) } ?? sorted[0].weightKg
        var slope = 0.0
        var cursor = start
        var lastReading = start

        while cursor <= end {
            let raw = byDay[cursor].map { $0.reduce(0, +) / Double($0.count) }
            if let raw {
                let gap = max(1, Double(cal.dateComponents([.day], from: lastReading, to: cursor).day ?? 1))
                let alpha = 1 - exp(-gap / timeConstant)
                let beta = 1 - exp(-gap / slopeConstant)
                let previous = level
                level = alpha * raw + (1 - alpha) * (level + slope * gap)
                slope = beta * ((level - previous) / gap) + (1 - beta) * slope
                slope = min(max(slope, -0.3), 0.3)   // nothing real moves faster than this
                lastReading = cursor
            }
            out.append(TrendPoint(date: cursor, raw: raw, trend: level, slopePerDay: slope))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    /// Kilograms a week the weight is moving, fitted by least squares over the window.
    ///
    /// The regression runs on the actual readings rather than on the smoothed line. A straight line
    /// through every reading is the unbiased way to measure a rate: noise cancels out across three
    /// weeks, and unlike the difference between two days no single reading can swing the answer.
    /// The smoothed line is for looking at; this is for deciding with. When there are too few
    /// readings to regress, the ends of the smoothed line are used instead.
    static func weeklyRate(_ points: [TrendPoint], overDays days: Int = 21) -> Double? {
        guard points.count >= 8 else { return nil }
        let cal = Calendar.current
        let window = Array(points.suffix(max(7, days)))
        guard let first = window.first, let last = window.last else { return nil }
        let span = Double(cal.dateComponents([.day], from: first.date, to: last.date).day ?? 0)
        guard span >= 7 else { return nil }

        func dayOffset(_ date: Date) -> Double {
            Double(cal.dateComponents([.day], from: first.date, to: date).day ?? 0)
        }

        let readings = window.compactMap { point -> (Double, Double)? in
            point.raw.map { (dayOffset(point.date), $0) }
        }
        guard readings.count >= 5 else { return (last.trend - first.trend) / span * 7 }

        let n = Double(readings.count)
        let meanX = readings.reduce(0) { $0 + $1.0 } / n
        let meanY = readings.reduce(0) { $0 + $1.1 } / n
        var numerator = 0.0, denominator = 0.0
        for (x, y) in readings {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return (last.trend - first.trend) / span * 7 }
        return numerator / denominator * 7
    }

    static func latestTrend(_ points: [TrendPoint]) -> Double? { points.last?.trend }

    /// How far today's reading sits from the trend. Useful for saying "that is water, not fat".
    static func deviation(_ points: [TrendPoint]) -> Double? {
        guard let last = points.last, let raw = last.raw else { return nil }
        return raw - last.trend
    }

    // MARK: What your burn really is

    struct EnergyEstimate: Equatable {
        var tdee: Int
        var days: Int
        var loggedDays: Int
        var weeklyRateKg: Double
        var averageIntake: Int
        /// 0 to 1. Low when there are few days or the logging is patchy, and the app blends the
        /// estimate toward the predicted number by this much.
        var confidence: Double
        var blended: Int

        var isTrustworthy: Bool { confidence >= 0.5 }
    }

    /// Your maintenance calories worked out from what you actually ate and what the trend line did.
    ///
    /// This beats any prediction equation once there is enough data, because it measures you rather
    /// than the average of a study population. It needs honest logging: patchy days make it read
    /// high, so the result is blended toward the predicted figure until the record is good enough.
    static func adaptiveTDEE(intakeByDay: [(date: Date, calories: Double?)],
                             trend: [TrendPoint],
                             predictedTDEE: Double,
                             windowDays: Int = 28) -> EnergyEstimate? {
        let cal = Calendar.current
        guard let lastTrendDate = trend.last?.date else { return nil }
        let startDate = cal.date(byAdding: .day, value: -windowDays, to: lastTrendDate) ?? lastTrendDate

        let window = trend.filter { $0.date >= startDate }
        guard let firstPoint = window.first, let lastPoint = window.last else { return nil }
        let span = Double(cal.dateComponents([.day], from: firstPoint.date, to: lastPoint.date).day ?? 0)
        guard span >= 13 else { return nil }

        let intake = intakeByDay.filter {
            let day = cal.startOfDay(for: $0.date)
            return day >= startDate && day <= lastTrendDate
        }
        let logged = intake.compactMap(\.calories).filter { $0 > 400 }
        guard logged.count >= 10 else { return nil }
        let averageIntake = logged.reduce(0, +) / Double(logged.count)

        let change = lastPoint.trend - firstPoint.trend
        let measured = averageIntake - change * NutritionMath.kcalPerKg / span

        let coverage = Double(logged.count) / (span + 1)
        let lengthScore = min(1, span / 28)
        let confidence = max(0, min(1, coverage * 0.7 + lengthScore * 0.3))
        let blended = measured * confidence + predictedTDEE * (1 - confidence)

        // A result that lands somewhere impossible means the log or the scale is wrong, not the
        // metabolism. Sustained loss past about 1.5 percent of body weight a week is not fat.
        guard measured > predictedTDEE * 0.55, measured < predictedTDEE * 1.7 else { return nil }
        let weeklyRate = change / span * 7
        guard abs(weeklyRate) <= 0.015 * max(lastPoint.trend, 40) else { return nil }

        return EnergyEstimate(tdee: Int(measured.rounded()),
                              days: Int(span) + 1,
                              loggedDays: logged.count,
                              weeklyRateKg: weeklyRate,
                              averageIntake: Int(averageIntake.rounded()),
                              confidence: confidence,
                              blended: Int((blended / 10).rounded() * 10))
    }

    // MARK: Is it working

    enum Verdict: Equatable {
        case onTrack(rateKg: Double)
        case faster(rateKg: Double)
        case slower(rateKg: Double)
        case stalled
        case wrongWay(rateKg: Double)
        case notEnoughData

        var isProblem: Bool {
            switch self {
            case .onTrack, .notEnoughData: return false
            default: return true
            }
        }
    }

    /// Compares the trend line with the pace the plan is aiming for.
    static func verdict(rate: Double?, goal: Goal, targetRateKg: Double) -> Verdict {
        guard let rate else { return .notEnoughData }
        let target = goal == .lose ? -abs(targetRateKg) : (goal == .gain ? abs(targetRateKg) : 0)

        if goal == .maintain || goal == .recomp {
            return abs(rate) <= 0.2 ? .onTrack(rateKg: rate) : (rate > 0 ? .faster(rateKg: rate) : .slower(rateKg: rate))
        }
        if target == 0 { return .onTrack(rateKg: rate) }
        if rate * target < 0 { return abs(rate) < 0.05 ? .stalled : .wrongWay(rateKg: rate) }
        if abs(rate) < 0.05 { return .stalled }

        let ratio = rate / target
        if ratio < 0.5 { return .slower(rateKg: rate) }
        if ratio > 1.6 { return .faster(rateKg: rate) }
        return .onTrack(rateKg: rate)
    }

    /// Plain words for the verdict, and what to do about it.
    static func advice(_ verdict: Verdict, goal: Goal, units: UnitSystem) -> (title: String, detail: String)? {
        func rate(_ kg: Double) -> String {
            let v = units == .metric ? kg : Units.kgToLb(kg)
            return String(format: "%.2f %@ a week", abs(v), units == .metric ? "kg" : "lb")
        }
        switch verdict {
        case .notEnoughData:
            return ("Keep weighing in", "Two weeks of readings and the trend line can tell you what is really happening.")
        case .onTrack(let r):
            return ("On track", "The trend is moving \(rate(r)), which is what the plan expects.")
        case .stalled:
            return goal == .lose
                ? ("Stalled", "Two weeks with no movement usually means portions have crept up or your burn has come down. Check the measured burn below before cutting calories again.")
                : ("Stalled", "The trend has not moved. Add about 150 calories a day and give it two weeks.")
        case .slower(let r):
            return goal == .lose
                ? ("Slower than planned", "The trend is moving \(rate(r)). Nothing is broken. If you want the original pace, take about 150 calories a day off the target.")
                : ("Slower than planned", "Moving \(rate(r)). Add about 150 calories a day.")
        case .faster(let r):
            return goal == .lose
                ? ("Faster than planned", "Losing \(rate(r)) is quicker than is useful. Muscle goes with fat at this speed. Add about 150 calories a day.")
                : ("Faster than planned", "Gaining \(rate(r)) is quicker than muscle can be built, so the extra is fat. Take about 150 calories a day off.")
        case .wrongWay(let r):
            return ("Going the other way", "The trend is moving \(rate(r)) in the wrong direction. Worth checking that the log covers everything, drinks and cooking oil included.")
        }
    }

    // MARK: Logging quality

    /// Share of the last `days` days with something logged. The honesty of everything above depends
    /// on this number.
    static func adherence(intakeByDay: [(date: Date, calories: Double?)], days: Int = 14) -> Double {
        let recent = intakeByDay.suffix(days)
        guard !recent.isEmpty else { return 0 }
        let logged = recent.filter { ($0.calories ?? 0) > 400 }.count
        return Double(logged) / Double(recent.count)
    }
}
