import SwiftUI
import SwiftData

/// Review an estimate before it is logged: adjust portions, ask the model to fix something, then save.
struct ResultEditorView: View {
    @State var meal: AnalyzedMeal
    var image: UIImage?
    var profile: Profile
    var day: Date
    var onLogged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var correction = ""
    @State private var fixing = false
    @State private var error: String?
    @State private var time = Date()
    @State private var saveFood = false

    private var canFix: Bool { [.photo, .label, .describe].contains(meal.source) }

    /// Scaling every item at once is free, instant, and fixes the thing that is actually wrong most
    /// of the time, which is how much was on the plate rather than what was on it.
    static let scales: [(label: String, factor: Double)] = [
        ("Half", 0.5), ("Three quarters", 0.75), ("A bit more", 1.25), ("Half again", 1.5), ("Double", 2),
    ]

    /// True when the model itself said it was unsure, or when it hedged on any single item.
    private var isUnsure: Bool {
        if let overall = meal.confidence, overall < 0.7 { return true }
        return meal.items.contains { ($0.confidence ?? 1) < 0.6 }
    }

    private func scaleAll(_ factor: Double) {
        for index in meal.items.indices {
            meal.items[index].quantity = (meal.items[index].quantity * factor * 100).rounded() / 100
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 200).clipped().listRowInsets(EdgeInsets())
                    }
                }
                if canFix, isUnsure {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Check the portion", systemImage: "questionmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("The food is usually right. How much of it there was is the guess, and it is the number that moves your day. Tap to scale the whole meal, or say what was different below.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                ForEach(Self.scales, id: \.label) { scale in
                                    Button(scale.label) { scaleAll(scale.factor) }
                                        .font(.footnote.weight(.semibold))
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    TextField("Meal name", text: $meal.name)
                    DatePicker("Time", selection: $time)
                }
                Section {
                    ForEach($meal.items) { $item in
                        ItemEditorRow(name: item.name, unit: item.unit, gramsPerUnit: item.gramsPerUnit,
                                      base: item.base, confidence: item.confidence, quantity: $item.quantity)
                    }
                    .onDelete { meal.items.remove(atOffsets: $0) }
                } header: {
                    Text("Items")
                } footer: {
                    if !meal.notes.isEmpty { Text(meal.notes) }
                }
                Section("Total") {
                    TotalsGrid(n: meal.totals)
                    if let score = meal.healthScore {
                        LabeledContent("Health score", value: "\(score) / 10")
                    }
                    if let c = meal.confidence {
                        LabeledContent("Confidence", value: c >= 0.75 ? "High" : c >= 0.5 ? "Medium" : "Low")
                    }
                }
                if canFix {
                    Section {
                        TextField("\"That was brown rice, about two cups\"", text: $correction, axis: .vertical)
                            .lineLimit(1...4)
                        Button {
                            fix()
                        } label: {
                            HStack {
                                if fixing { ProgressView() }
                                Text(fixing ? "Re-estimating" : "Fix results")
                            }
                        }
                        .disabled(correction.trimmingCharacters(in: .whitespaces).isEmpty || fixing)
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    } header: {
                        Text("Something wrong?")
                    } footer: {
                        Text("Tell it what the photo could not show. The whole meal is re-estimated around your correction.")
                    }
                }
                Section {
                    Toggle("Also save as a food", isOn: $saveFood)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { log() }.bold().disabled(meal.items.isEmpty || fixing)
                }
            }
            .onAppear {
                // Log to the selected day at the current clock time.
                let cal = Calendar.current
                let now = Date()
                time = cal.date(bySettingHour: cal.component(.hour, from: now), minute: cal.component(.minute, from: now), second: 0, of: day) ?? now
            }
        }
    }

    private func fix() {
        fixing = true
        error = nil
        Task {
            do {
                meal = try await FoodAnalyzer(context: .init(profile: profile)).fix(meal, image: image, correction: correction)
                correction = ""
            } catch {
                self.error = error.localizedDescription
            }
            fixing = false
        }
    }

    private func log() {
        let entry = MealEntry(name: meal.name.isEmpty ? "Meal" : meal.name, date: time, source: meal.source)
        entry.notes = meal.notes
        entry.healthScore = meal.healthScore
        entry.confidence = meal.confidence
        if let image { entry.imageData = AIClient.downscaled(image, maxSide: 900).jpegData(compressionQuality: 0.75) }
        for (i, item) in meal.items.enumerated() {
            entry.items.append(MealItem(name: item.name, quantity: item.quantity, unit: item.unit, gramsPerUnit: item.gramsPerUnit,
                                        base: item.base, confidence: item.confidence, order: i))
        }
        entry.recalculate()
        context.insert(entry)
        if saveFood {
            context.insert(SavedFood(name: entry.name, servingLabel: "meal", servingGrams: nil, perServing: entry.totals))
        }
        try? context.save()
        if profile.writeToHealth { Task { await HealthStore.shared.write(meal: entry) } }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onLogged()
    }
}
