import SwiftUI
import SwiftData

/// Edit a logged meal: name, time, portions. Totals recalculate from the items on every change.
struct MealDetailView: View {
    @Bindable var meal: MealEntry
    var profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var saveAsFood = false

    var body: some View {
        NavigationStack {
            Form {
                if let data = meal.imageData, let img = UIImage(data: data) {
                    Section {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(height: 200).clipped()
                            .listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    TextField("Name", text: $meal.name)
                    DatePicker("Time", selection: $meal.date)
                }
                Section("Items") {
                    ForEach(meal.items.sorted(by: { $0.order < $1.order })) { item in
                        ItemEditorRow(name: item.name, unit: item.unit, gramsPerUnit: item.gramsPerUnit,
                                      base: item.base, confidence: item.confidence,
                                      quantity: Binding(get: { item.quantity }, set: { item.quantity = $0; meal.recalculate() }))
                    }
                    .onDelete { offsets in
                        let sorted = meal.items.sorted(by: { $0.order < $1.order })
                        for i in offsets { context.delete(sorted[i]) }
                        meal.items.removeAll { item in offsets.contains { sorted[$0].id == item.id } }
                        meal.recalculate()
                    }
                }
                Section("Totals") {
                    TotalsGrid(n: meal.totals)
                    if let score = meal.healthScore {
                        LabeledContent("Health score", value: "\(score) / 10")
                    }
                    if !meal.notes.isEmpty {
                        Text(meal.notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Save as a food for quick logging", systemImage: "bookmark") {
                        let food = SavedFood(name: meal.name, servingLabel: "meal", servingGrams: nil, perServing: meal.totals)
                        context.insert(food)
                        saveAsFood = true
                    }
                    .disabled(saveAsFood)
                    Button("Delete meal", systemImage: "trash", role: .destructive) {
                        if profile.writeToHealth { Task { await HealthStore.shared.delete(meal: meal) } }
                        context.delete(meal)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        meal.recalculate()
                        try? context.save()
                        if profile.writeToHealth { Task { await HealthStore.shared.write(meal: meal) } }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ItemEditorRow: View {
    var name: String
    var unit: String
    var gramsPerUnit: Double?
    var base: Nutrients
    var confidence: Double?
    @Binding var quantity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((base.calories * quantity).rounded())) kcal").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Stepper(value: $quantity, in: 0...99, step: stepSize) {
                    HStack(spacing: 4) {
                        NumberField(title: "qty", value: $quantity, decimals: stepSize >= 10 ? 0 : 2).frame(width: 56)
                        Text(unit).foregroundStyle(.secondary)
                        if let g = gramsPerUnit {
                            Text("(\(Int((g * quantity).rounded())) g)").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.subheadline)
                }
            }
            HStack(spacing: 10) {
                Text("P \(Int((base.protein * quantity).rounded()))")
                Text("C \(Int((base.carbs * quantity).rounded()))")
                Text("F \(Int((base.fat * quantity).rounded()))")
                if let c = confidence, c < 0.6 {
                    Label("low confidence", systemImage: "questionmark.circle").foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var stepSize: Double {
        unit.lowercased().hasPrefix("g") || unit.lowercased().hasPrefix("ml") ? 10 : 0.5
    }
}

struct TotalsGrid: View {
    var n: Nutrients

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            GridRow { cell("Calories", "\(Int(n.calories.rounded()))"); cell("Protein", "\(Int(n.protein.rounded())) g") }
            GridRow { cell("Carbs", "\(Int(n.carbs.rounded())) g"); cell("Fat", "\(Int(n.fat.rounded())) g") }
            GridRow { cell("Fiber", "\(Int(n.fiber.rounded())) g"); cell("Sugar", "\(Int(n.sugar.rounded())) g") }
            GridRow { cell("Sodium", "\(Int(n.sodium.rounded())) mg"); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
        }
    }

    private func cell(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}
