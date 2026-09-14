import SwiftUI
import SwiftData
import Charts

/// Weight trend, calorie history, and the reality check that corrects the target from real data.
struct ProgressView_: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @State private var range = 30
    @State private var logging = false
    @State private var newWeightKg: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    weightCard
                    if let check = realityCheck { realityCard(check) }
                    intakeCard
                    statsCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            .sheet(isPresented: $logging) { logWeightSheet }
        }
    }

    // MARK: Weight

    private var latestWeight: Double { weights.last?.weightKg ?? profile.weightKg }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight").font(.footnote).foregroundStyle(.secondary)
                    Text(Units.weightString(latestWeight, profile.units)).font(.system(.title, design: .rounded).weight(.bold))
                }
                Spacer()
                if profile.goal != .maintain {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Goal").font(.footnote).foregroundStyle(.secondary)
                        Text(Units.weightString(profile.targetWeightKg, profile.units, decimals: 0)).font(.headline)
                    }
                }
            }
            if weights.count >= 2 {
                Chart {
                    ForEach(weights) { w in
                        LineMark(x: .value("Date", w.date), y: .value("kg", display(w.weightKg)))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Date", w.date), y: .value("kg", display(w.weightKg)))
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(20)
                    }
                    if profile.goal != .maintain {
                        RuleMark(y: .value("Goal", display(profile.targetWeightKg)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 160)
            } else {
                Text("Log a few weights to see the trend. Same time of day, same conditions, and ignore single-day swings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                let bmi = NutritionMath.bmi(weightKg: latestWeight, heightCm: profile.heightCm)
                Text(String(format: "BMI %.1f, %@", bmi, NutritionMath.bmiLabel(bmi))).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Log weight", systemImage: "plus") { newWeightKg = latestWeight; logging = true }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .card()
    }

    private func display(_ kg: Double) -> Double { profile.units == .metric ? kg : Units.kgToLb(kg) }

    private var yDomain: ClosedRange<Double> {
        let values = weights.map { display($0.weightKg) } + (profile.goal != .maintain ? [display(profile.targetWeightKg)] : [])
        let lo = (values.min() ?? 0) - 2, hi = (values.max() ?? 100) + 2
        return lo...hi
    }

    private var logWeightSheet: some View {
        NavigationStack {
            Form {
                WeightField(title: "Weight", kg: $newWeightKg, units: profile.units)
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { logging = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(WeightEntry(weightKg: newWeightKg))
                        profile.weightKg = newWeightKg
                        if profile.writeToHealth { Task { await HealthStore.shared.write(weightKg: newWeightKg, date: Date()) } }
                        logging = false
                    }
                    .disabled(newWeightKg < 20)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    // MARK: Reality check

    private var realityCheck: NutritionMath.RealityCheck? {
        guard let first = weights.first, let last = weights.last else { return nil }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        guard days >= 14 else { return nil }
        let intake = DayStats.dailyCalories(meals: meals, days: days, endingOn: last.date).compactMap { $0.1 }
        return NutritionMath.realityCheck(intakeByDay: intake, startWeightKg: first.weightKg, endWeightKg: last.weightKg,
                                          days: days, goal: profile.goal, paceKgPerWeek: profile.paceKgPerWeek)
    }

    private func realityCard(_ c: NutritionMath.RealityCheck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Reality check", systemImage: "scalemass").font(.headline)
            Text("Over \(c.days) days you averaged \(c.averageIntake) kcal and your weight changed by \(String(format: "%+.1f", display(c.weightChangeKg))) \(profile.units == .metric ? "kg" : "lb"). That puts your real maintenance near \(c.impliedTDEE) kcal.")
                .font(.subheadline)
            if abs(c.suggestedCalories - profile.calorieTarget) >= 100 {
                HStack {
                    Text("Suggested target: \(c.suggestedCalories) kcal").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Apply") {
                        profile.calorieTarget = c.suggestedCalories
                        let plan = NutritionMath.plan(for: profile.inputs)
                        let ratio = Double(c.suggestedCalories) / Double(max(plan.calories, 1))
                        profile.carbTarget = Int((Double(plan.carbs) * ratio).rounded())
                        profile.fatTarget = Int((Double(plan.fat) * ratio).rounded())
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else {
                Text("Your current target of \(profile.calorieTarget) kcal is on track.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Intake

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calories").font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.menu)
            }
            let series = DayStats.dailyCalories(meals: meals, days: range)
            Chart {
                ForEach(series, id: \.0) { day, kcal in
                    if let kcal {
                        BarMark(x: .value("Day", day, unit: .day), y: .value("kcal", kcal))
                            .foregroundStyle(kcal > Double(profile.calorieTarget) * 1.1 ? Color.red.opacity(0.8) : Color.accentColor)
                            .cornerRadius(3)
                    }
                }
                RuleMark(y: .value("Target", profile.calorieTarget))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .frame(height: 160)
            let logged = series.compactMap { $0.1 }
            if !logged.isEmpty {
                let avg = Int((logged.reduce(0, +) / Double(logged.count)).rounded())
                Text("Average \(avg) kcal over \(logged.count) logged \(logged.count == 1 ? "day" : "days"), target \(profile.calorieTarget).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Stats

    private var statsCard: some View {
        let series = DayStats.dailyCalories(meals: meals, days: range)
        let days = series.compactMap { $0.1 }.count
        let macros = meals.filter { m in series.contains { DayStats.sameDay($0.0, m.date) && $0.1 != nil } }
            .reduce(Nutrients.zero) { $0 + $1.totals }
        let n = max(days, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Averages, last \(range) days").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow { avgCell("Protein", macros.protein / Double(n), profile.proteinTarget, "g"); avgCell("Carbs", macros.carbs / Double(n), profile.carbTarget, "g") }
                GridRow { avgCell("Fat", macros.fat / Double(n), profile.fatTarget, "g"); avgCell("Fiber", macros.fiber / Double(n), nil, "g") }
                GridRow { avgCell("Sugar", macros.sugar / Double(n), nil, "g"); avgCell("Sodium", macros.sodium / Double(n), nil, "mg") }
            }
            let streak = DayStats.streak(meals: meals)
            Text("Streak \(streak) \(streak == 1 ? "day" : "days"). \(days) of \(range) days logged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .card()
    }

    private func avgCell(_ label: String, _ value: Double, _ target: Int?, _ unit: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value.rounded()))\(target.map { " / \($0)" } ?? "") \(unit)").monospacedDigit()
        }
        .font(.subheadline)
    }
}
