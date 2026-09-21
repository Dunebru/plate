import SwiftUI

/// A number, logged.
///
/// Not every meal is worth photographing. Someone who already knows a packet was 240 calories, or who
/// ate something the camera will never identify, should be able to say so in four seconds rather than
/// abandon the day's log over it. A day with a rough number in it beats a day with a hole.
struct QuickAddView: View {
    var onResult: (AnalyzedMeal) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @FocusState private var focus: Field?

    private enum Field { case name, calories, protein, carbs, fat }

    private var kcal: Double { Double(calories) ?? 0 }
    private var canSave: Bool { kcal > 0 }

    /// Macros are optional. When they are left out the calories still count, and when they are given
    /// they are shown against the calories so an obvious slip is visible before it is saved.
    private var fromMacros: Double {
        (Double(protein) ?? 0) * 4 + (Double(carbs) ?? 0) * 4 + (Double(fat) ?? 0) * 9
    }

    private var mismatch: Bool {
        fromMacros > 20 && kcal > 0 && abs(fromMacros - kcal) / kcal > 0.25
    }

    var body: some View {
        Form {
            Section {
                TextField("Calories", text: $calories)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .calories)
                TextField("What was it? Optional", text: $name)
                    .focused($focus, equals: .name)
            } header: {
                Text("Quick add")
            } footer: {
                Text("Only the calories are needed. Anything you leave out is counted as zero, so the day's macros will read a little low.")
            }

            Section("Macros, if you know them") {
                macroField("Protein", $protein, .protein, unit: "g")
                macroField("Carbs", $carbs, .carbs, unit: "g")
                macroField("Fat", $fat, .fat, unit: "g")
            }

            if mismatch {
                Section {
                    Label("Those macros work out to about \(Int(fromMacros.rounded())) calories, not \(Int(kcal)). One of the two is probably a typo.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Quick add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }.bold().disabled(!canSave)
            }
        }
        .onAppear { focus = .calories }
    }

    private func macroField(_ title: String, _ value: Binding<String>, _ field: Field, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .focused($focus, equals: field)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = AnalyzedMeal.Item(
            name: label.isEmpty ? "Quick add" : label,
            quantity: 1,
            unit: "serving",
            gramsPerUnit: nil,
            base: Nutrients(calories: kcal,
                            protein: Double(protein) ?? 0,
                            carbs: Double(carbs) ?? 0,
                            fat: Double(fat) ?? 0,
                            fiber: 0, sugar: 0, sodium: 0),
            // Typed by hand, so it is as certain as anything in the log gets.
            confidence: 1)
        onResult(AnalyzedMeal(name: label.isEmpty ? "Quick add" : label,
                              items: [item],
                              notes: "",
                              healthScore: nil,
                              confidence: 1,
                              source: .manual))
        dismiss()
    }
}
