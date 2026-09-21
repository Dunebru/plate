import SwiftData
import SwiftUI

/// Log something again.
///
/// People eat the same handful of things. Re-photographing the same breakfast every morning is the
/// fastest way to stop logging altogether, and it also spends a scan on an answer already stored.
/// This lists what has actually been eaten, most recent first, and logs it again in one tap.
struct RepeatMealView: View {
    var onResult: (AnalyzedMeal) -> Void
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// One row per distinct meal, keeping the most recent version of each. Someone who eats porridge
    /// every day wants one porridge, not thirty.
    private var recent: [MealEntry] {
        var seen = Set<String>()
        var out: [MealEntry] = []
        for meal in meals where !meal.items.isEmpty {
            let key = meal.name.lowercased().trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(meal)
            if out.count == 60 { break }
        }
        return out
    }

    private var shown: [MealEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return recent }
        return recent.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        Group {
            if recent.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "Nothing to repeat yet",
                               message: "Once you have logged a few meals they show up here, ready to log again in one tap.")
            } else {
                List {
                    ForEach(shown) { meal in
                        Button { pick(meal) } label: { row(meal) }
                            .buttonStyle(.plain)
                    }
                }
                .searchable(text: $search, prompt: "Search what you have eaten")
            }
        }
        .navigationTitle("Log it again")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ meal: MealEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: meal.source.symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name).font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(meal.items.count) \(meal.items.count == 1 ? "item" : "items") \u{00B7} \(relative(meal.date))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(Int(meal.totals.calories.rounded()))")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        return days < 7 ? "\(days) days ago" : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Copied by value. The old entry keeps its own date and its own numbers, so editing the portion
    /// on the copy cannot reach back and rewrite history.
    private func pick(_ meal: MealEntry) {
        let items = meal.items.sorted { $0.order < $1.order }.map { item in
            AnalyzedMeal.Item(name: item.name, quantity: item.quantity, unit: item.unit,
                              gramsPerUnit: item.gramsPerUnit, base: item.base,
                              confidence: item.confidence)
        }
        onResult(AnalyzedMeal(name: meal.name, items: items, notes: meal.notes,
                              healthScore: meal.healthScore, confidence: meal.confidence,
                              source: meal.source, fromEstimate: false))
        dismiss()
    }
}
