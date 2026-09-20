import SwiftUI
import SwiftData

/// One tape measure session. Every field is optional, because measuring one thing beats measuring
/// nothing, and the waist alone already says a lot.
struct MeasureSheet: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var weightKg: Double?
    /// Keyed by `BodyMeasurement.Field.key`, always in centimeters whatever the user types in.
    @State private var lengths: [String: Double] = [:]
    @State private var note = ""
    @State private var saves = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    BodyEntryField(label: "Weight", symbol: "scalemass", kind: .weight,
                                   units: profile.units, value: $weightKg)
                }
                Section {
                    ForEach(BodyMeasurement.fields) { field in
                        BodyEntryField(label: field.label, symbol: field.symbol, tip: field.tip,
                                       units: profile.units, value: binding(for: field.key))
                    }
                } header: {
                    Text("Tape measure")
                } footer: {
                    Text("Same time of day every time, ideally first thing in the morning. Tape snug against the skin without squeezing.")
                }
                Section {
                    preview
                } header: {
                    Text("Body fat")
                }
                Section {
                    TextField("Anything worth remembering", text: $note, axis: .vertical)
                } header: {
                    Text("Note")
                }
            }
            .navigationTitle("New measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!hasNumbers)
                }
            }
            .sensoryFeedback(.success, trigger: saves)
        }
    }

    // MARK: Live estimate

    private var estimate: Double? {
        guard let neck = lengths["neck"], let waist = lengths["waist"] else { return nil }
        return BodyComposition.navyBodyFat(sex: profile.sex, heightCm: profile.heightCm,
                                           neckCm: neck, waistCm: waist, hipCm: lengths["hip"])
    }

    @ViewBuilder private var preview: some View {
        if let percent = estimate {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", percent))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let band = BodyBandScale.band(for: percent, sex: profile.sex) {
                        Text(band.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                BodyBandScale(percent: percent, sex: profile.sex)
                Text(BodyComposition.Source.tape.confidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: percent)
        } else {
            Text(missingForEstimate)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingForEstimate: String {
        var missing: [String] = []
        if lengths["neck"] == nil { missing.append("neck") }
        if lengths["waist"] == nil { missing.append("waist") }
        if profile.sex == .female, lengths["hip"] == nil { missing.append("hips") }
        if missing.isEmpty {
            return "Those numbers do not give a sensible estimate. Worth checking the tape and trying again."
        }
        return "Add your \(BodyText.list(missing)) and the estimate appears here."
    }

    // MARK: Saving

    private var hasNumbers: Bool { weightKg != nil || !lengths.isEmpty }

    private func binding(for key: String) -> Binding<Double?> {
        Binding(
            get: { lengths[key] },
            set: { new in
                if let new {
                    lengths[key] = new
                } else {
                    lengths.removeValue(forKey: key)
                }
            })
    }

    private func save() {
        let entry = BodyMeasurement(date: date)
        entry.weightKg = weightKg
        for field in BodyMeasurement.fields {
            entry.setValue(lengths[field.key], for: field.key)
        }
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(entry)
        // The tape formula needs height and sex, which the measurement itself does not carry.
        entry.refreshBodyFat(sex: profile.sex, heightCm: profile.heightCm, fallbackWeightKg: profile.weightKg)

        // The calorie math reads these off the profile, so the newest numbers have to land there too.
        if let neck = entry.neckCm { profile.neckCm = neck }
        if let waist = entry.waistCm { profile.waistCm = waist }
        if let hip = entry.hipCm { profile.hipCm = hip }
        // A tape reading taken today beats a number typed in weeks ago, so stop preferring the old one.
        if entry.bodyFatSource == .tape { profile.enteredBodyFat = nil }
        if let kg = entry.weightKg {
            profile.weightKg = kg
            // Logged separately so the weight trend on the Progress tab sees it.
            context.insert(WeightEntry(date: date, weightKg: kg))
            if profile.writeToHealth {
                Task { await HealthStore.shared.write(weightKg: kg, date: date) }
            }
        }
        if !profile.targetsEditedByUser { profile.recalculateTargets() }

        saves += 1
        dismiss()
    }
}
