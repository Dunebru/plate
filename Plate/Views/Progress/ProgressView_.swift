import SwiftUI
import SwiftData
import Charts

/// The weekly check in. Where the trend line is going, whether the plan is working, what the body
/// really burns, and where the current target lands.
///
/// Everything here is measured from the smoothed trend rather than the last reading on the scale,
/// because a single weigh in is mostly water.
struct ProgressView_: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @StateObject private var health = HealthStore.shared

    @State private var range: ProgressRange = .month
    @State private var intakeDays = 30
    @State private var logging = false
    @State private var newWeightKg: Double = 0
    @State private var importing = false
    @State private var note: String?
    @State private var applied = 0

    private var fmt: ProgressWeightFormat { ProgressWeightFormat(units: profile.units) }

    private var samples: [TrendEngine.Sample] {
        weights.map { TrendEngine.Sample(date: $0.date, weightKg: $0.weightKg) }
    }

    private var latestReading: Double { weights.last?.weightKg ?? profile.weightKg }

    var body: some View {
        NavigationStack {
            ScrollView {
                let trend = TrendEngine.trend(samples)
                VStack(spacing: 14) {
                    weightCard(trend)
                    verdictCard(trend)
                    burnCard(trend)
                    forecastCard(trend)
                    intakeCard
                    consistencyCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            // The burn card reads this snapshot, so it has to be filled before the card can use it.
            // Silent and cheap when the wearable switch is off, which is the normal case.
            .task { await health.refreshSignals(prediction: .init(profile.inputs)) }
            .sheet(isPresented: $logging) { logWeightSheet }
            .sensoryFeedback(.success, trigger: applied)
            .sensoryFeedback(.increase, trigger: weights.count)
        }
    }

    // MARK: Weight

    private func weightCard(_ trend: [TrendEngine.TrendPoint]) -> some View {
        let end = trend.last?.date ?? Date()
        let start = range.start(endingOn: end)
        let shown = start.map { cutoff in trend.filter { $0.date >= cutoff } } ?? trend

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                ProgressCardTitle(text: "Weight trend", symbol: "chart.xyaxis.line")
                Spacer(minLength: 8)
                if profile.goal.changesWeight {
                    Text("Goal \(fmt.string(profile.targetWeightKg, decimals: 0))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressHeadline(value: fmt.string(TrendEngine.latestTrend(trend) ?? profile.weightKg),
                             caption: readingCaption(trend))

            if shown.count >= 2 {
                weightChart(shown)
                Picker("Range", selection: $range) {
                    ForEach(ProgressRange.allCases) { r in Text(r.label).tag(r) }
                }
                .pickerStyle(.segmented)
            } else {
                ProgressChartPlaceholder(symbol: "scalemass",
                                         title: "Two weigh ins and the line appears",
                                         message: "Weigh yourself at the same time of day, before eating. The trend needs a few readings before it means anything.")
            }

            HStack(spacing: 10) {
                Button {
                    newWeightKg = latestReading
                    logging = true
                } label: {
                    Label("Log weight", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if HealthStore.available {
                    Button {
                        importFromHealth()
                    } label: {
                        if importing {
                            SwiftUI.ProgressView().controlSize(.mini)
                        } else {
                            Label("Health", systemImage: "heart.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(importing)
                    .accessibilityLabel("Import the latest weight from Apple Health")
                }
                Spacer(minLength: 0)
            }

            if let note {
                ProgressNote(text: note, symbol: "checkmark.circle")
            }
        }
        .card()
    }

    private func weightChart(_ points: [TrendEngine.TrendPoint]) -> some View {
        Chart {
            ForEach(points) { p in
                if let raw = p.raw {
                    PointMark(x: .value("Day", p.date),
                              y: .value("Weight", fmt.display(raw)))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .symbolSize(16)
                }
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date),
                         y: .value("Trend", fmt.display(p.trend)))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
            }
            if profile.goal.changesWeight {
                RuleMark(y: .value("Goal", fmt.display(profile.targetWeightKg)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYScale(domain: weightDomain(points))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxisLabel(fmt.suffix)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Weight trend chart")
    }

    private func weightDomain(_ points: [TrendEngine.TrendPoint]) -> ClosedRange<Double> {
        var values = points.map { fmt.display($0.trend) }
        values += points.compactMap { $0.raw.map { fmt.display($0) } }
        if profile.goal.changesWeight { values.append(fmt.display(profile.targetWeightKg)) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.18, profile.units == .metric ? 0.6 : 1.3)
        return (lo - pad)...(hi + pad)
    }

    /// The raw reading, said in a way that does not let a salty dinner read as fat.
    private func readingCaption(_ trend: [TrendEngine.TrendPoint]) -> String {
        guard let last = trend.last, let raw = last.raw else {
            return "Trend weight, smoothed across about ten days."
        }
        let cal = Calendar.current
        let when: String
        if cal.isDateInToday(last.date) { when = "Today" }
        else if cal.isDateInYesterday(last.date) { when = "Yesterday" }
        else { when = last.date.formatted(.dateTime.month(.abbreviated).day()) }

        guard let dev = TrendEngine.deviation(trend), abs(dev) >= 0.3 else {
            return "\(when) read \(fmt.string(raw)), right on the trend."
        }
        if dev > 0 {
            return "\(when) read \(fmt.string(raw)), \(fmt.gap(dev)) above the trend. Salt, carbs and a full gut move the scale that much overnight, so the line is the number to steer by."
        }
        return "\(when) read \(fmt.string(raw)), \(fmt.gap(dev)) below the trend. A light reading is water too. Wait for the line to follow before believing it."
    }

    private var logWeightSheet: some View {
        NavigationStack {
            Form {
                ProgressWeightField(title: "Weight", kg: $newWeightKg, units: profile.units)
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { logging = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveWeight() }
                        .disabled(newWeightKg < 20)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private func saveWeight() {
        let kg = newWeightKg
        context.insert(WeightEntry(weightKg: kg))
        profile.weightKg = kg
        try? context.save()
        if profile.writeToHealth {
            Task { await HealthStore.shared.write(weightKg: kg, date: Date()) }
        }
        note = nil
        logging = false
    }

    private func importFromHealth() {
        importing = true
        Task {
            if !health.authorized { await health.requestAuthorization() }
            let latest = await health.latestWeight()
            importing = false
            guard let (date, kg) = latest else {
                note = "Nothing to import. Apple Health has no weight, or access is off in Settings."
                return
            }
            let known = weights.contains { DayStats.sameDay($0.date, date) && abs($0.weightKg - kg) < 0.05 }
            if !known { context.insert(WeightEntry(date: date, weightKg: kg, fromHealth: true)) }
            profile.weightKg = kg
            try? context.save()
            note = known
                ? "Already had \(fmt.string(kg)) from \(date.formatted(.dateTime.month(.abbreviated).day()))."
                : "Imported \(fmt.string(kg)) from \(date.formatted(.dateTime.month(.abbreviated).day()))."
        }
    }

    // MARK: Verdict

    private func verdictCard(_ trend: [TrendEngine.TrendPoint]) -> some View {
        let rate = TrendEngine.weeklyRate(trend)
        let planPace = profile.plan.paceKgPerWeek
        let verdict = TrendEngine.verdict(rate: rate, goal: profile.goal, targetRateKg: planPace)
        let advice = TrendEngine.advice(verdict, goal: profile.goal, units: profile.units)
        let tint: Color = rate == nil ? .secondary : (verdict.isProblem ? .orange : .green)

        return HStack(alignment: .top, spacing: 12) {
            ProgressAccentBar(color: tint)
            VStack(alignment: .leading, spacing: 8) {
                ProgressCardTitle(text: "Is it working", symbol: "target")
                Text(advice?.title ?? "Keep weighing in")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(advice?.detail ?? "Two weeks of readings and the trend line can tell you what is really happening.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let rate {
                    HStack(alignment: .top, spacing: 18) {
                        pair("Trend", fmt.rate(rate))
                        if profile.goal.changesWeight {
                            pair("Plan", fmt.rate(profile.goal == .lose ? -planPace : planPace))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .card()
    }

    private func pair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
        }
    }

    // MARK: Measured burn

    private func burnCard(_ trend: [TrendEngine.TrendPoint]) -> some View {
        let endDate = trend.last?.date ?? Date()
        // A little more than the 28 day window the estimate uses, so nothing gets clipped.
        let intake = intakeSeries(days: 35, endingOn: endDate)
        let predicted = NutritionMath.tdee(profile.inputs)
        // A wearable's number is a better starting guess than an equation, so it stands in as the
        // prior that energy balance is measured against. It is not the answer on its own: a device
        // models a burn, it does not weigh anyone.
        let prior = HealthSignals.prior(measured: health.signals.burn, predictedTDEE: predicted)
        let estimate = TrendEngine.adaptiveTDEE(intakeByDay: intake, trend: trend, predictedTDEE: prior)
        let wearable = health.signals.burn

        return VStack(alignment: .leading, spacing: 12) {
            ProgressCardTitle(text: "Measured burn", symbol: "flame")
            if let e = estimate {
                ProgressHeadline(value: "\(e.tdee) kcal",
                                 caption: "Maintenance worked out from \(e.days) days of trend, \(e.loggedDays) of them with food logged.")
                ProgressConfidenceBar(confidence: e.confidence)
                HStack(alignment: .top, spacing: 18) {
                    pair(wearable == nil ? "Predicted" : "Starting point",
                         "\(Int(prior.rounded())) kcal")
                    pair("Average intake", "\(e.averageIntake) kcal")
                    Spacer(minLength: 0)
                }
                if e.isTrustworthy, abs(e.blended - profile.calorieTarget) >= 100 {
                    Button {
                        applyMeasuredTarget(e.blended)
                    } label: {
                        Label("Set target to \(e.blended) kcal", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    ProgressNote(text: "That figure is pulled partway back toward the prediction while the record is short, so the target never jumps somewhere wild.")
                } else if e.isTrustworthy {
                    Text("Your target of \(profile.calorieTarget) kcal already matches what the scale and the log say.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Too thin a record to act on yet. Keep logging and this firms up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let wearable {
                    ProgressNote(text: "Started from \(wearable.source.label), which read \(wearable.tdee) kcal over \(wearable.days > 0 ? "\(wearable.days) days" : "\(wearable.sessions) sessions"). What you weigh and what you eat still decide the figure above.",
                                 symbol: "applewatch")
                }
                ProgressNote(text: "This measures you. A prediction equation only ever averages a study population.",
                             symbol: "person.crop.circle.badge.checkmark")
            } else {
                Text("Not measurable yet")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                ForEach(burnNeeds(trend, intake: intake), id: \.self) { need in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                        Text(need).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                ProgressNote(text: "Once the record is long enough this replaces the predicted burn, because it measures you rather than a population average.",
                             symbol: "person.crop.circle.badge.checkmark")
            }
        }
        .card()
    }

    /// Exactly what is still missing, in the same terms the estimate demands.
    private func burnNeeds(_ trend: [TrendEngine.TrendPoint], intake: [(date: Date, calories: Double?)]) -> [String] {
        let cal = Calendar.current
        guard let last = trend.last else {
            return ["A first weigh in. Two weeks of readings after that and the burn can be measured."]
        }
        let start = cal.date(byAdding: .day, value: -28, to: last.date) ?? last.date
        let window = trend.filter { $0.date >= start }
        let span = cal.dateComponents([.day], from: window.first?.date ?? last.date, to: last.date).day ?? 0
        let logged = intake
            .filter { $0.date >= start && $0.date <= last.date }
            .compactMap(\.calories)
            .filter { $0 > 400 }
            .count

        var needs: [String] = []
        if span < 13 {
            let missing = 13 - span
            needs.append("\(missing) more \(missing == 1 ? "day" : "days") between your first and last weigh in, 14 in all.")
        }
        if logged < 10 {
            let missing = 10 - logged
            needs.append("\(missing) more logged \(missing == 1 ? "day" : "days") of food in the last four weeks, 10 in all.")
        }
        if needs.isEmpty {
            needs.append("The scale and the log do not agree closely enough to trust. That is usually missed days, drinks, or cooking oil rather than a strange metabolism.")
        }
        return needs
    }

    private func applyMeasuredTarget(_ calories: Int) {
        profile.calorieTarget = calories
        let m = NutritionMath.macros(calories: Double(calories), inputs: profile.inputs)
        profile.proteinTarget = m.protein
        profile.carbTarget = m.carbs
        profile.fatTarget = m.fat
        profile.fiberTarget = NutritionMath.fiberTarget(calories: Double(calories))
        // A measured figure beats the prediction, so a later recalculation should not quietly undo it.
        profile.targetsEditedByUser = true
        try? context.save()
        applied += 1
    }

    // MARK: Forecast

    private func forecastCard(_ trend: [TrendEngine.TrendPoint]) -> some View {
        var inputs = profile.inputs
        // Start from the trend, not from one reading, or the whole curve inherits today's water.
        if let t = TrendEngine.latestTrend(trend) { inputs.weightKg = t }
        let points = NutritionMath.projection(for: inputs, calorieTarget: profile.calorieTarget, weeks: 26)
        let goalDate = profile.goal.changesWeight
            ? NutritionMath.projectedGoalDate(for: inputs, calorieTarget: profile.calorieTarget, targetKg: profile.targetWeightKg)
            : nil
        let chartEnd = points.last?.date ?? Date()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                ProgressCardTitle(text: "Forecast", symbol: "calendar")
                Spacer(minLength: 8)
                Text("\(profile.calorieTarget) kcal a day")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressHeadline(value: fmt.string(points.last?.weightKg ?? inputs.weightKg),
                             caption: "Where 26 weeks at the current target lands you.")

            if points.count >= 2 {
                forecastChart(points, goalDate: goalDate, chartEnd: chartEnd)
            } else {
                ProgressChartPlaceholder(symbol: "calendar",
                                         title: "Nothing to forecast",
                                         message: "Set a calorie target and a goal weight and the curve appears here.")
            }

            if let goalDate {
                let within = goalDate <= chartEnd
                Label(within
                      ? "Crosses \(fmt.string(profile.targetWeightKg, decimals: 0)) around \(goalDate.formatted(.dateTime.month(.wide).day().year()))."
                      : "At this target the goal lands around \(goalDate.formatted(.dateTime.month(.wide).year())), past the right edge of this chart.",
                      systemImage: "flag.checkered")
                    .font(.footnote.weight(.medium))
            } else if profile.goal.changesWeight {
                Label("This target never reaches the goal weight. Move the pace or the target.", systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }

            ProgressNote(text: "The curve flattens because burn falls as body mass does. That is why a straight line forecast always overpromises.",
                         symbol: "chart.line.downtrend.xyaxis")
        }
        .card()
    }

    private func forecastChart(_ points: [NutritionMath.ProjectionPoint], goalDate: Date?, chartEnd: Date) -> some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date),
                         y: .value("Weight", fmt.display(p.weightKg)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date),
                         y: .value("Weight", fmt.display(p.weightKg)))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
            }
            if profile.goal.changesWeight {
                RuleMark(y: .value("Goal", fmt.display(profile.targetWeightKg)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color.secondary)
            }
            if let goalDate, goalDate <= chartEnd {
                RuleMark(x: .value("Goal date", goalDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.green)
            }
        }
        .chartYScale(domain: forecastDomain(points))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxisLabel(fmt.suffix)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Forecast chart")
    }

    private func forecastDomain(_ points: [NutritionMath.ProjectionPoint]) -> ClosedRange<Double> {
        var values = points.map { fmt.display($0.weightKg) }
        if profile.goal.changesWeight { values.append(fmt.display(profile.targetWeightKg)) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.18, profile.units == .metric ? 0.6 : 1.3)
        return (lo - pad)...(hi + pad)
    }

    // MARK: Intake

    private func intakeSeries(days: Int, endingOn end: Date) -> [(date: Date, calories: Double?)] {
        DayStats.dailyCalories(meals: meals, days: days, endingOn: end).map { (date: $0.0, calories: $0.1) }
    }

    private var intakeCard: some View {
        let series = intakeSeries(days: intakeDays, endingOn: Date())
        let bars = series.map { ProgressDayCalories(day: $0.date, calories: $0.calories) }
        let logged = series.compactMap(\.calories)
        let adherence = TrendEngine.adherence(intakeByDay: series, days: intakeDays)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                ProgressCardTitle(text: "What you ate", symbol: "fork.knife")
                Spacer(minLength: 8)
                Picker("Window", selection: $intakeDays) {
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.menu)
            }

            if logged.isEmpty {
                ProgressChartPlaceholder(symbol: "fork.knife",
                                         title: "No meals logged yet",
                                         message: "Log a few days of food and the honest version of your burn can be worked out.")
            } else {
                let mean = logged.reduce(0, +) / Double(logged.count)
                ProgressHeadline(value: "\(Int(mean.rounded())) kcal",
                                 caption: "Average across \(logged.count) logged \(logged.count == 1 ? "day" : "days"), target \(profile.calorieTarget).")
                Chart {
                    ForEach(bars) { d in
                        if let kcal = d.calories {
                            BarMark(x: .value("Day", d.day, unit: .day),
                                    y: .value("Calories", kcal))
                                .foregroundStyle(kcal > Double(profile.calorieTarget) * 1.1 ? Color.orange : Color.accentColor)
                                .cornerRadius(3)
                        }
                    }
                    RuleMark(y: .value("Target", profile.calorieTarget))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(Color.secondary)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxisLabel("kcal")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 150)
                .accessibilityLabel("Daily calories chart")

                ProgressNote(text: "Logged \(Int((adherence * 100).rounded())) percent of the last \(intakeDays) days. Every number on this screen is only as honest as that.",
                             symbol: "checklist")
            }
        }
        .card()
    }

    // MARK: Streak and totals

    private var consistencyCard: some View {
        let series = intakeSeries(days: intakeDays, endingOn: Date())
        let loggedDays = series.filter { ($0.calories ?? 0) > 0 }.count
        let windowStart = series.first?.date ?? Date()
        let totals = meals.filter { $0.date >= windowStart }.reduce(Nutrients.zero) { $0 + $1.totals }
        let n = Double(max(loggedDays, 1))
        let streak = DayStats.streak(meals: meals)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ProgressStatTile(value: "\(streak)", label: "day streak",
                                 symbol: "flame.fill", tint: streak > 0 ? .orange : .secondary)
                ProgressStatTile(value: "\(loggedDays)/\(intakeDays)", label: "days logged", symbol: "checklist")
                ProgressStatTile(value: "\(weights.count)", label: "weigh ins", symbol: "scalemass")
            }

            Divider()

            ProgressCardTitle(text: "Daily averages, last \(intakeDays) days", symbol: "chart.bar")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    ProgressMetricRow(label: "Protein", value: average(totals.protein / n, target: profile.proteinTarget, unit: "g"))
                    ProgressMetricRow(label: "Carbs", value: average(totals.carbs / n, target: profile.carbTarget, unit: "g"))
                }
                GridRow {
                    ProgressMetricRow(label: "Fat", value: average(totals.fat / n, target: profile.fatTarget, unit: "g"))
                    ProgressMetricRow(label: "Fiber", value: average(totals.fiber / n, target: profile.fiberTarget, unit: "g"))
                }
                GridRow {
                    ProgressMetricRow(label: "Sugar", value: average(totals.sugar / n, target: nil, unit: "g"))
                    ProgressMetricRow(label: "Sodium", value: average(totals.sodium / n, target: nil, unit: "mg"))
                }
            }
        }
        .card()
    }

    private func average(_ value: Double, target: Int?, unit: String) -> String {
        let rounded = Int(value.rounded())
        guard let target else { return "\(rounded) \(unit)" }
        return "\(rounded) / \(target) \(unit)"
    }
}
