import SwiftUI
import SwiftData

struct HomeView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @StateObject private var health = HealthStore.shared
    @State private var day = Date()
    @State private var showAdd = false
    @State private var editing: MealEntry?

    private var dayMeals: [MealEntry] { meals.filter { DayStats.sameDay($0.date, day) } }
    private var totals: Nutrients { dayMeals.reduce(Nutrients.zero) { $0 + $1.totals } }
    private var streak: Int { DayStats.streak(meals: meals) }

    private var calorieTarget: Int {
        var t = profile.calorieTarget
        if profile.rolloverCalories { t += DayStats.rollover(target: profile.calorieTarget, meals: meals, today: day) }
        if profile.addExerciseCalories, Calendar.current.isDateInToday(day) { t += Int(health.activeEnergyToday) }
        return t
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WeekStrip(selected: $day, meals: meals)
                    summaryCard
                    HStack(spacing: 10) {
                        MacroCard(title: "Protein", eaten: totals.protein, target: Double(profile.proteinTarget), color: .protein)
                        MacroCard(title: "Carbs", eaten: totals.carbs, target: Double(profile.carbTarget), color: .carbs)
                        MacroCard(title: "Fat", eaten: totals.fat, target: Double(profile.fatTarget), color: .fat)
                    }
                    secondaryRow
                    mealList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) { addButton }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(day.dayTitle)
            .toolbar {
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
            .task { await health.refreshToday() }
            .refreshable { await health.refreshToday() }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 20) {
            CalorieRing(eaten: totals.calories, target: Double(calorieTarget))
                .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 12) {
                stat("Eaten", "\(Int(totals.calories.rounded()))", "fork.knife")
                stat("Target", "\(calorieTarget)", "target")
                if profile.addExerciseCalories || health.activeEnergyToday > 0 {
                    stat("Burned", "\(Int(health.activeEnergyToday))", "figure.run")
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func stat(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.headline, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 10) {
            miniStat("Fiber", "\(Int(totals.fiber.rounded())) g")
            miniStat("Sugar", "\(Int(totals.sugar.rounded())) g")
            miniStat("Sodium", "\(Int(totals.sodium.rounded())) mg")
            if health.stepsToday > 0 { miniStat("Steps", health.stepsToday.formatted()) }
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var mealList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logged").font(.headline).padding(.top, 6)
            if dayMeals.isEmpty {
                EmptyStateView(symbol: "camera.viewfinder", title: "Nothing logged yet",
                               message: "Tap the plus to photograph a meal, scan a barcode, or describe what you ate.")
                    .card()
            } else {
                ForEach(dayMeals) { meal in
                    Button { editing = meal } label: { MealRow(meal: meal) }
                        .buttonStyle(.plain)
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
                    withAnimation(.snappy) { selected = day }
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(isSelected ? .white : .secondary)
                        Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? .white : .primary)
                        Circle().fill(logged ? (isSelected ? Color.white : Color.accentColor) : Color.clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
