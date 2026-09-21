import SwiftUI

/// One of the six nutrients Today can explain. Everything that differs between them lives here so
/// the sheet is written once rather than six times.
enum BreakdownNutrient: String, Identifiable, CaseIterable {
    case protein, carbs, fat, fiber, sugar, sodium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .fiber: return "Fiber"
        case .sugar: return "Sugar"
        case .sodium: return "Sodium"
        }
    }

    /// Sodium is the only one of the six measured in milligrams.
    var unit: String { self == .sodium ? "mg" : "g" }

    var color: Color {
        switch self {
        case .protein: return .protein
        case .carbs: return .carbs
        case .fat: return .fat
        case .fiber: return .fiber
        case .sugar: return .sugar
        case .sodium: return .sodium
        }
    }

    /// Sugar and sodium are ceilings, where staying under is the good outcome. The other four are
    /// targets, where reaching them is. The sheet reads this rather than guessing from the name.
    var isLimit: Bool { self == .sugar || self == .sodium }

    func amount(in n: Nutrients) -> Double {
        switch self {
        case .protein: return n.protein
        case .carbs: return n.carbs
        case .fat: return n.fat
        case .fiber: return n.fiber
        case .sugar: return n.sugar
        case .sodium: return n.sodium
        }
    }

    func goal(for profile: Profile) -> Int {
        switch self {
        case .protein: return profile.proteinTarget
        case .carbs: return profile.carbTarget
        case .fat: return profile.fatTarget
        case .fiber: return profile.fiberTarget
        case .sugar: return profile.sugarLimit
        case .sodium: return profile.sodiumLimit
        }
    }

    /// Plate can only ever see total sugar, while the limit is for added sugar, so a day of fruit
    /// would otherwise read as a failure. The sentence lives with the limit it explains rather than
    /// here, so the number and the caveat cannot drift apart.
    var caveat: String? { self == .sugar ? NutritionMath.totalVersusAddedSugarNote : nil }
}

/// One item's share of a nutrient on one day. Items rather than meals, because the useful answer is
/// which food did it, not which sitting it happened at.
struct NutrientContribution: Identifiable {
    let id: UUID
    let name: String
    let mealName: String
    let date: Date
    let amount: Double

    /// Every item logged on `day`, biggest contributor first. A meal with no items stands in for
    /// itself, so an entry saved before items existed still shows up in the ranking.
    static func ranked(_ nutrient: BreakdownNutrient, meals: [MealEntry], day: Date) -> [NutrientContribution] {
        var rows: [NutrientContribution] = []
        for meal in meals where DayStats.sameDay(meal.date, day) {
            if meal.items.isEmpty {
                rows.append(NutrientContribution(id: meal.id, name: meal.name, mealName: meal.name,
                                                 date: meal.date, amount: nutrient.amount(in: meal.totals)))
            } else {
                for item in meal.items.sorted(by: { $0.order < $1.order }) {
                    rows.append(NutrientContribution(id: item.id, name: item.name, mealName: meal.name,
                                                     date: meal.date, amount: nutrient.amount(in: item.scaled)))
                }
            }
        }
        // Anything that rounds to nothing is noise in a ranking, so it is left out.
        return rows.filter { $0.amount.rounded() > 0 }.sorted {
            $0.amount == $1.amount ? $0.date < $1.date : $0.amount > $1.amount
        }
    }
}

/// What gave you the day's protein, carbs, fat, fiber, sugar or sodium, largest first.
struct NutrientBreakdownView: View {
    let nutrient: BreakdownNutrient
    var profile: Profile
    let meals: [MealEntry]
    let day: Date
    @Environment(\.dismiss) private var dismiss

    private var total: Double { nutrient.amount(in: DayStats.totals(on: day, meals: meals)) }
    private var rows: [NutrientContribution] { NutrientContribution.ranked(nutrient, meals: meals, day: day) }
    private var biggest: Double { rows.first?.amount ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if rows.isEmpty {
                        EmptyStateView(symbol: "fork.knife",
                                       title: "Nothing logged yet",
                                       message: "Log something and this will rank every item by how much \(nutrient.title.lowercased()) it gave you.")
                            .card()
                    } else {
                        list
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(nutrient.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: The day's number

    private var goal: Int { nutrient.goal(for: profile) }
    private var eaten: Int { Int(total.rounded()) }
    private var overLimit: Bool { nutrient.isLimit && goal > 0 && eaten > goal }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.dayTitle)
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(eaten.formatted())
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1)
                    .contentTransition(.numericText())
                    .foregroundStyle(overLimit ? Color.orange : Color.primary)
                Text(nutrient.unit)
                    .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Text(statusLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusTint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            GoalBar(fraction: goal > 0 ? min(total / Double(goal), 1) : 0, color: barTint)

            if let caveat = nutrient.caveat {
                Text(caveat)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statusLine: String {
        guard goal > 0 else { return "No target set for \(nutrient.title.lowercased())" }
        let limit = goal.formatted()
        if nutrient.isLimit {
            return eaten > goal
                ? "\((eaten - goal).formatted())\(nutrient.unit) over the \(limit)\(nutrient.unit) limit"
                : "\((goal - eaten).formatted())\(nutrient.unit) under the \(limit)\(nutrient.unit) limit"
        }
        return eaten >= goal
            ? "Target of \(limit)\(nutrient.unit) reached"
            : "\((goal - eaten).formatted())\(nutrient.unit) short of your \(limit)\(nutrient.unit) target"
    }

    private var statusTint: Color {
        guard goal > 0 else { return .secondary }
        if nutrient.isLimit { return overLimit ? .orange : .secondary }
        return eaten >= goal ? .reached : .secondary
    }

    private var barTint: Color { overLimit ? .orange : nutrient.color }

    // MARK: The ranking

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Where it came from").font(.headline)
                Spacer()
                Text("\(rows.count) \(rows.count == 1 ? "item" : "items")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ContributionRow(row: row,
                                share: total > 0 ? row.amount / total : 0,
                                fill: biggest > 0 ? row.amount / biggest : 0,
                                unit: nutrient.unit,
                                color: nutrient.color,
                                rank: index)
            }
        }
    }
}

/// The day against its target or limit. Fills on appear so the sheet has the same spring as the
/// dials it was opened from.
private struct GoalBar: View {
    var fraction: Double
    var color: Color
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.5, dampingFraction: 1), value: shown)
        .onAppear { shown = fraction }
        .onChange(of: fraction) { _, new in shown = new }
        .accessibilityHidden(true)
    }
}

/// One food, with the bar behind it showing how it compares to the biggest contributor.
private struct ContributionRow: View {
    let row: NutrientContribution
    let share: Double
    let fill: Double
    let unit: String
    let color: Color
    let rank: Int
    @State private var shown: Double = 0

    private var time: String { row.date.formatted(date: .omitted, time: .shortened) }
    /// Demo and single food entries name the meal after its only item, and repeating that reads as
    /// a mistake, so the time carries the row on its own.
    private var caption: String { row.mealName == row.name ? time : "\(row.mealName) · \(time)" }
    private var shareText: String { share >= 0.01 ? "\(Int((share * 100).rounded()))%" : "under 1%" }
    private var spokenUnit: String { unit == "mg" ? "milligrams" : "grams" }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(row.amount.rounded()).formatted())\(unit)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(shareText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(14)
        .background(alignment: .leading) {
            GeometryReader { geo in
                Rectangle().fill(color.opacity(0.20)).frame(width: geo.size.width * shown)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            // Stagger the fills a little so the ranking reads top down on the way in.
            withAnimation(.spring(response: 0.5, dampingFraction: 1).delay(Double(min(rank, 8)) * 0.04)) {
                shown = fill
            }
        }
        .onChange(of: fill) { _, new in shown = new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(caption), \(Int(row.amount.rounded())) \(spokenUnit), \(shareText) of the day")
    }
}
