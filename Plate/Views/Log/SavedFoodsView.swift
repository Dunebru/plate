import SwiftUI
import SwiftData

/// Foods and meals you log often, sorted by use. Also where custom foods are created.
struct SavedFoodsView: View {
    var onResult: (AnalyzedMeal) -> Void
    @Query(sort: \SavedFood.useCount, order: .reverse) private var foods: [SavedFood]
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var creating = false

    private var filtered: [SavedFood] {
        query.isEmpty ? foods : foods.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.brand.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if foods.isEmpty {
                EmptyStateView(symbol: "bookmark", title: "No saved foods",
                               message: "Save a logged meal from its detail screen, or create a custom food here.")
            }
            ForEach(filtered) { food in
                Button { pick(food) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text([food.brand, "per \(food.servingLabel)"].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(food.calories.rounded()))").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in for i in offsets { context.delete(filtered[i]) } }
        }
        .searchable(text: $query, prompt: "Filter")
        .navigationTitle("Saved foods")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) { CustomFoodView() }
    }

    private func pick(_ food: SavedFood) {
        food.useCount += 1
        food.lastUsed = Date()
        let name = food.brand.isEmpty ? food.name : "\(food.name) (\(food.brand))"
        onResult(AnalyzedMeal(name: food.name,
                              items: [.init(name: name, quantity: 1, unit: food.servingLabel, gramsPerUnit: food.servingGrams,
                                            base: food.perServing, confidence: 1)],
                              notes: "", healthScore: nil, confidence: 1, source: .saved))
    }
}

struct CustomFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var brand = ""
    @State private var servingLabel = "serving"
    @State private var servingGrams: Double = 100
    @State private var n = Nutrients()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
                Section("Serving") {
                    TextField("Serving name", text: $servingLabel)
                    HStack { Text("Grams per serving"); Spacer(); NumberField(title: "g", value: $servingGrams).frame(width: 80) }
                }
                Section("Per serving") {
                    row("Calories", $n.calories)
                    row("Protein (g)", $n.protein)
                    row("Carbs (g)", $n.carbs)
                    row("Fat (g)", $n.fat)
                    row("Fiber (g)", $n.fiber)
                    row("Sugar (g)", $n.sugar)
                    row("Sodium (mg)", $n.sodium)
                }
            }
            .navigationTitle("Custom food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(SavedFood(name: name, brand: brand, servingLabel: servingLabel,
                                                 servingGrams: servingGrams > 0 ? servingGrams : nil, perServing: n))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func row(_ label: String, _ value: Binding<Double>) -> some View {
        HStack { Text(label); Spacer(); NumberField(title: "0", value: value, decimals: 1).frame(width: 80) }
    }
}
