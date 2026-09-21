import SwiftData
import SwiftUI

struct HomeView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @StateObject private var health = HealthStore.shared
    @State private var day = Date()
    @State private var showAdd = false
    @State private var editing: MealEntry?
    @State private var breakdown: BreakdownNutrient?

    private var dayMeals: [MealEntry] { meals.filter { DayStats.sameDay($0.date, day) } }
    private var totals: Nutrients { dayMeals.reduce(Nutrients.zero) { $0 + $1.totals } }
    private var streak: Int { DayStats.streak(meals: meals) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// The number on the ring. Rollover and workout calories only apply to today.
    private var calorieTarget: Int {
        var target = profile.calorieTarget
        if let split = NutritionMath.daySplit(calories: profile.calorieTarget, cycling: profile.cycling,
                                              trainingDaysPerWeek: profile.trainingDaysPerWeek),
           profile.cycling == .weekends {
            let weekday = Calendar.current.component(.weekday, from: day)
            target = (weekday == 1 || weekday == 7) ? split.higher : split.lower
        }
        if profile.rolloverCalories { target += DayStats.rollover(target: profile.calorieTarget, meals: meals, today: day) }
        if profile.addExerciseCalories, isToday { target += Int(health.activeEnergyToday) }
        return target
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    WeekStrip(selected: $day, meals: meals)
                    hero
                    macroRow
                    microRow
                    mealList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { addButton }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(day.dayTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { PlanView(profile: profile) } label: {
                        Image(systemName: "list.clipboard")
                    }
                    .accessibilityLabel("Your plan")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? .orange : .secondary)
                        Text("\(streak)").font(.headline.monospacedDigit())
                    }
                    .accessibilityLabel("\(streak) day streak")
                }
            }
            .sheet(isPresented: $showAdd) { AddSheet(profile: profile, day: day) }
            .sheet(item: $editing) { meal in MealDetailView(meal: meal, profile: profile) }
            .sheet(item: $breakdown) { nutrient in
                NutrientBreakdownView(nutrient: nutrient, profile: profile, meals: meals, day: day)
            }
            .task { await health.refreshToday() }
            .refreshable { await health.refreshToday() }
        }
    }

    // MARK: Hero

    private var remaining: Int { calorieTarget - Int(totals.calories.rounded()) }

    private var hero: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(remaining >= 0 ? "Calories left" : "Over by")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Text("\(abs(remaining))")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // Large numerals read too far apart, and a grouped four digit figure plus the
                    // ring fills the width of the narrowest phone, so it shrinks rather than clips.
                    .tracking(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                HStack(spacing: 10) {
                    small("\(Int(totals.calories.rounded()))", "eaten")
                    small("\(calorieTarget)", "target")
                    if profile.addExerciseCalories, health.activeEnergyToday > 0 {
                        small("\(Int(health.activeEnergyToday))", "burned")
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            CalorieRing(eaten: totals.calories, target: Double(calorieTarget))
                .frame(width: 112, height: 112)
        }
        .card()
    }

    private func small(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Macros

    private var macroRow: some View {
        HStack(spacing: 10) {
            dial(.protein, eaten: totals.protein, target: profile.proteinTarget)
            dial(.carbs, eaten: totals.carbs, target: profile.carbTarget)
            dial(.fat, eaten: totals.fat, target: profile.fatTarget)
        }
    }

    private func dial(_ nutrient: BreakdownNutrient, eaten: Double, target: Int) -> some View {
        Button { breakdown = nutrient } label: {
            MacroDial(title: nutrient.title, eaten: eaten, target: Double(target), color: nutrient.color)
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Shows what gave you the most \(nutrient.title.lowercased()) today")
    }

    private var microRow: some View {
        HStack(spacing: 10) {
            microTile(.fiber, eaten: totals.fiber, goal: profile.fiberTarget)
            microTile(.sugar, eaten: totals.sugar, goal: profile.sugarLimit)
            microTile(.sodium, eaten: totals.sodium, goal: profile.sodiumLimit)
            if health.stepsToday > 0, isToday {
                micro("Steps", value: health.stepsToday.formatted(), goal: nil, tint: .primary,
                      spoken: "\(health.stepsToday.formatted()) steps")
            }
        }
    }

    /// Fiber is a target, so reaching it is green. Sugar and sodium are limits, so being under one
    /// is simply normal and only going over is worth a color.
    private func microTile(_ nutrient: BreakdownNutrient, eaten: Double, goal: Int) -> some View {
        let amount = Int(eaten.rounded())
        let tint: Color = nutrient.isLimit
            ? (amount > goal ? .orange : .primary)
            : (amount >= goal ? .green : .primary)
        let unit = nutrient.unit
        return Button { breakdown = nutrient } label: {
            micro(nutrient.title, value: amount.formatted(), goal: "/ \(goal.formatted()) \(unit)", tint: tint,
                  spoken: "\(amount.formatted()) of \(goal.formatted()) \(unit == "mg" ? "milligrams" : "grams")")
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Shows what gave you the most \(nutrient.title.lowercased()) today")
    }

    private func micro(_ label: String, value: String, goal: String?, tint: Color, spoken: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                if let goal {
                    Text(goal).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(spoken)")
    }

    // MARK: Meals

    private var mealList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Logged").font(.headline)
                Spacer()
                if !dayMeals.isEmpty {
                    Text("\(dayMeals.count) \(dayMeals.count == 1 ? "meal" : "meals")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)

            if dayMeals.isEmpty {
                EmptyStateView(symbol: "camera.viewfinder", title: "Nothing logged yet",
                               message: "Tap the plus to photograph a meal, scan a barcode, or just describe what you ate.")
                    .card()
            } else {
                ForEach(dayMeals) { meal in
                    Button { editing = meal } label: { MealRow(meal: meal) }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button("Copy to today", systemImage: "doc.on.doc") { copy(meal) }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(meal) }
                        }
                }
            }
        }
    }

    private var addButton: some View {
        HStack {
            Spacer()
            Button { showAdd = true } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Log food")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func delete(_ meal: MealEntry) {
        if profile.writeToHealth { Task { await HealthStore.shared.delete(meal: meal) } }
        context.delete(meal)
    }

    private func copy(_ meal: MealEntry) {
        let copy = MealEntry(name: meal.name, date: Date(), source: meal.source)
        copy.notes = meal.notes
        copy.healthScore = meal.healthScore
        copy.imageData = meal.imageData
        for (i, item) in meal.items.sorted(by: { $0.order < $1.order }).enumerated() {
            copy.items.append(MealItem(name: item.name, quantity: item.quantity, unit: item.unit,
                                       gramsPerUnit: item.gramsPerUnit, base: item.base, confidence: item.confidence, order: i))
        }
        copy.recalculate()
        context.insert(copy)
        if profile.writeToHealth { Task { await HealthStore.shared.write(meal: copy) } }
    }
}

/// A macro as a dial rather than a bar, so three of them read at a glance.
struct MacroDial: View {
    var title: String
    var eaten: Double
    var target: Double
    var color: Color
    @State private var shown: Double = 0

    private var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }
    private var left: Int { Int((target - eaten).rounded()) }
    private var done: Bool { target > 0 && eaten >= target }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(color)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(spacing: -1) {
                        Text("\(max(left, 0))")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text("left").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(width: 40)
                }
            }
            .frame(height: 56)
            .animation(.spring(response: 0.5, dampingFraction: 1), value: shown)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: done)

            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(Int(eaten.rounded())) / \(Int(target)) g")
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { shown = fraction }
        .onChange(of: fraction) { _, new in shown = new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Int(eaten.rounded())) of \(Int(target)) grams\(done ? ", target reached" : "")")
    }
}

struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(meal.date.formatted(date: .omitted, time: .shortened))
                    Text("P \(Int(meal.protein.rounded()))  C \(Int(meal.carbs.rounded()))  F \(Int(meal.fat.rounded()))").monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(meal.calories.rounded()))").font(.system(.headline, design: .rounded)).monospacedDigit()
        }
        .card()
    }

    private var thumbnail: some View {
        Group {
            if let data = meal.imageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: meal.source.symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Seven-day strip with a dot under days that have entries.
struct WeekStrip: View {
    @Binding var selected: Date
    var meals: [MealEntry]

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isSelected = DayStats.sameDay(day, selected)
                let logged = meals.contains { DayStats.sameDay($0.date, day) }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 1)) { selected = day }
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(isSelected ? .white : .secondary)
                        Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? .white : .primary)
                        Circle().fill(logged ? (isSelected ? Color.white : Color.accentColor) : Color.clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isSelected)
            }
        }
    }
}
