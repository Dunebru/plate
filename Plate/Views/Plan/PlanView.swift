import Charts
import SwiftUI

/// The whole plan, and the arithmetic behind it. Nothing here is a black box: every number shows
/// its working, because a target you understand is one you will actually follow.
struct PlanView: View {
    @Bindable var profile: Profile
    @Environment(\.dismiss) private var dismiss
    @State private var showSources = false

    private var inputs: NutritionMath.Inputs { profile.inputs }
    private var plan: NutritionMath.Plan { NutritionMath.plan(for: inputs) }
    private var split: NutritionMath.DaySplit? {
        NutritionMath.daySplit(calories: profile.calorieTarget, cycling: profile.cycling,
                               trainingDaysPerWeek: profile.trainingDaysPerWeek)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                macros
                if let split { cycling(split) }
                workings
                if profile.goal.changesWeight { forecast }
                extras
                if !profile.focusAreas.isEmpty { focus }
                footer
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSources) { NavigationStack { SourcesView() } }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Text("Daily target").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            Text("\(profile.calorieTarget)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("calories").font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 0) {
                pill(profile.goal.label, profile.goal.symbol)
                if plan.dailyDelta != 0 {
                    Divider().frame(height: 22)
                    pill(plan.dailyDelta < 0 ? "\(abs(plan.dailyDelta)) under burn" : "\(plan.dailyDelta) over burn",
                         plan.dailyDelta < 0 ? "arrow.down" : "arrow.up")
                }
                if plan.paceKgPerWeek > 0 {
                    Divider().frame(height: 22)
                    pill(Units.weightString(plan.paceKgPerWeek, profile.units, decimals: 2) + " a week", "speedometer")
                }
            }
            .padding(.top, 2)

            if let note = plan.note {
                Label(note, systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func pill(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    // MARK: Macros

    private var macros: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Macros", "A day's worth")
            HStack(spacing: 10) {
                macroTile("Protein", profile.proteinTarget, .protein, plan.proteinKcal)
                macroTile("Carbs", profile.carbTarget, .carbs, plan.carbKcal)
                macroTile("Fat", profile.fatTarget, .fat, plan.fatKcal)
            }
            let meals = profile.mealPattern.mealCount
            if meals > 1 {
                Text("Across \(meals) meals that is about \(profile.proteinTarget / meals) g of protein and \(profile.calorieTarget / meals) calories each.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func macroTile(_ name: String, _ grams: Int, _ color: Color, _ kcal: Int) -> some View {
        VStack(spacing: 6) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(grams)").font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
            Text("g").font(.caption2).foregroundStyle(.secondary)
            Capsule().fill(color).frame(height: 4)
            Text("\(percent(kcal))%").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(grams) grams, \(percent(kcal)) percent of calories")
    }

    private func percent(_ kcal: Int) -> Int {
        profile.calorieTarget > 0 ? Int((Double(kcal) / Double(profile.calorieTarget) * 100).rounded()) : 0
    }

    // MARK: Uneven days

    private func cycling(_ split: NutritionMath.DaySplit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Not every day the same", profile.cycling.label)
            HStack(spacing: 10) {
                dayTile(split.label, split.higher, .accentColor)
                dayTile(split.label == "Training days" ? "Rest days" : "Weekdays", split.lower, .secondary)
            }
            Text("Same weekly total, spread to match your week. Eating more around training gives the hard sessions something to run on.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func dayTile(_ name: String, _ calories: Int, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(calories)").font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Showing the working

    private var workings: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("How this was worked out", plan.method)
            line("Resting burn", "\(plan.bmr)", "What you would burn asleep all day.")
            if let daily = profile.dailyActivity {
                line("Everyday movement", "x \(String(format: "%.2f", daily.pal))", daily.label + ", before any training.")
            } else {
                line("Activity", "x \(String(format: "%.3f", profile.activity.multiplier))", profile.activity.label)
            }
            let training = NutritionMath.trainingKcalPerDay(inputs)
            if training > 0 {
                line("Training", "+ \(Int(training.rounded()))",
                     "\(profile.trainingDaysPerWeek) x \(profile.trainingMinutes) min of \(profile.trainingStyle.label.lowercased()), averaged over the week.")
            }
            Divider()
            line("Daily burn", "\(plan.tdee)", "Everything above, added up.")
            if plan.dailyDelta != 0 {
                line(plan.dailyDelta < 0 ? "Deficit" : "Surplus", "\(plan.dailyDelta)",
                     plan.dailyDelta < 0 ? "Held below your burn so the fat comes off." : "Kept small so the gain is mostly muscle.")
            }
            Divider()
            line("Your target", "\(profile.calorieTarget)", nil, bold: true)
        }
        .card()
    }

    private func line(_ name: String, _ value: String, _ detail: String?, bold: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(bold ? .subheadline.weight(.bold) : .subheadline)
                Spacer()
                Text(value)
                    .font(.system(bold ? .headline : .subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Forecast

    private var points: [NutritionMath.ProjectionPoint] {
        NutritionMath.projection(for: inputs, calorieTarget: profile.calorieTarget, weeks: 26)
    }

    private var forecast: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Where this lands", "Next six months")
            if let date = NutritionMath.projectedGoalDate(for: inputs, calorieTarget: profile.calorieTarget, targetKg: profile.targetWeightKg) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Units.weightString(profile.targetWeightKg, profile.units, decimals: 0))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("around \(date.formatted(.dateTime.month(.wide).day()))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Week", point.date),
                             y: .value("Weight", display(point.weightKg)))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Week", point.date),
                             y: .value("Weight", display(point.weightKg)))
                        .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("Goal", display(profile.targetWeightKg)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.narrow)) } }
            .frame(height: 140)
            Text("The curve flattens because a lighter body burns less. Holding the same calories means the gap narrows every week, which is why a straight line forecast always promises too much.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func display(_ kg: Double) -> Double {
        profile.units == .metric ? kg : Units.kgToLb(kg)
    }

    // MARK: Everything else

    private var extras: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Also worth hitting", nil)
            line("Fiber", "\(profile.fiberTarget)g", "14g per 1,000 calories. It is what makes a deficit bearable.")
            line("Water", "\(String(format: "%.1f", Double(profile.waterMl) / 1000)) L", "Roughly 35 ml per kilogram, plus what training costs.")
            if profile.drinksPerWeek > 0 {
                line("Alcohol", "\(profile.drinksPerWeek) a week", "About \(profile.drinksPerWeek * 120) calories, before what it does to the next day's appetite.")
            }
        }
        .card()
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("What you are working on", profile.areaGoal.label)
            ForEach(profile.focusAreas) { area in
                NavigationLink {
                    FocusPlanView(area: area, profile: profile)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: area.symbol).foregroundStyle(Color.accentColor).frame(width: 24)
                        Text(area.label).font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Text(FocusGuidance.spotReductionNote).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
        }
        .card()
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                profile.recalculateTargets()
            } label: {
                Label("Recalculate from my answers", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Where these numbers come from") { showSources = true }
                .font(.footnote)
        }
        .padding(.top, 4)
    }

    private func sectionTitle(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
