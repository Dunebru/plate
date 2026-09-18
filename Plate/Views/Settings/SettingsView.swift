import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @State private var provider: AIProvider = .current
    @State private var apiKey = Keychain.get(AIProvider.current.keyAccount) ?? ""
    @AppStorage(ClaudeClient.modelDefaultsKey) private var model = ClaudeClient.defaultModel
    @State private var keyStatus: OnboardingView.KeyStatus = .idle
    @State private var exportURL: URL?
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Targets") {
                    row("Calories", $profile.calorieTarget, "kcal")
                    row("Protein", $profile.proteinTarget, "g")
                    row("Carbs", $profile.carbTarget, "g")
                    row("Fat", $profile.fatTarget, "g")
                    Button("Recalculate from my stats") { profile.recalculateTargets() }
                    NavigationLink { SourcesView() } label: { Label("How these numbers are calculated", systemImage: "book") }
                    Text("Editing calories does not change the macros. Recalculate to get a matching set.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Me") {
                    Picker("Units", selection: $profile.units) { ForEach(UnitSystem.allCases) { Text($0.label).tag($0) } }
                    Picker("Sex", selection: $profile.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    Picker("Birth year", selection: $profile.birthYear) {
                        ForEach((1930...Calendar.current.component(.year, from: Date()) - 13).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                    HeightField(profile: profile)
                    WeightField(title: "Weight", kg: $profile.weightKg, units: profile.units)
                    Picker("Activity", selection: $profile.activity) { ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) } }
                    Picker("Goal", selection: $profile.goal) { ForEach(Goal.allCases) { Text($0.label).tag($0) } }
                    if profile.goal != .maintain {
                        WeightField(title: "Target weight", kg: $profile.targetWeightKg, units: profile.units)
                        PaceSlider(profile: profile)
                    }
                }

                Section("Daily budget") {
                    Toggle("Add workout calories", isOn: $profile.addExerciseCalories)
                    Toggle("Roll over unused calories", isOn: $profile.rolloverCalories)
                }

                Section {
                    Toggle("Sync with Apple Health", isOn: $profile.writeToHealth)
                        .onChange(of: profile.writeToHealth) { _, on in if on { Task { await HealthStore.shared.requestAuthorization() } } }
                    Button("Import latest weight from Health") {
                        Task {
                            if let (date, kg) = await HealthStore.shared.latestWeight() {
                                context.insert(WeightEntry(date: date, weightKg: kg, fromHealth: true))
                                profile.weightKg = kg
                            }
                        }
                    }
                    .disabled(!profile.writeToHealth)
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Meals are written as dietary energy, protein, carbs, fat, fiber, sugar, and sodium. Editing or deleting a meal updates Health.")
                }

                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) { _, p in AIProvider.current = p; apiKey = Keychain.get(p.keyAccount) ?? ""; keyStatus = .idle }
                    SecureField(provider.keyPlaceholder, text: $apiKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onChange(of: apiKey) { _, k in Keychain.set(k.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keyAccount); keyStatus = .idle }
                    HStack {
                        Button("Test key") { test() }.disabled(apiKey.isEmpty)
                        Spacer()
                        switch keyStatus {
                        case .idle: EmptyView()
                        case .checking: ProgressView()
                        case .ok: Label("Works", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed(let why): Text(why).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                    if provider == .anthropic {
                        Picker("Model", selection: $model) {
                            ForEach(ClaudeClient.models, id: \.id) { m in
                                VStack(alignment: .leading) { Text(m.label); Text(m.note).font(.caption).foregroundStyle(.secondary) }.tag(m.id)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } header: {
                    Text("Photo analysis")
                } footer: {
                    Text("\(provider.consoleHint) Needed for photo, label, and description logging. Stored in the keychain, sent only to \(provider.host). Barcodes and search use Open Food Facts and need no key.")
                }

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share meals.csv", systemImage: "square.and.arrow.up") }
                    } else {
                        Button("Export meals as CSV", systemImage: "tablecells") { exportURL = exportCSV() }
                    }
                    Button("Reset everything", systemImage: "trash", role: .destructive) { confirmReset = true }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Link("Source on GitHub", destination: URL(string: "https://github.com/Dunebru/plate")!)
                    Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                    NavigationLink("Sources and medical disclaimer") { SourcesView() }
                    Text("Estimates from a photo are typically within 10 to 30 percent. Check the portions, correct what is wrong, and trust the weekly trend over any single number.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all meals, weights, saved foods, and your profile?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { reset() }
            }
        }
    }

    private func row(_ label: String, _ value: Binding<Int>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            NumberField(title: "0", value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })).frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func test() {
        keyStatus = .checking
        Task {
            do { try await AIClient(provider: provider).verifyKey(); keyStatus = .ok }
            catch { keyStatus = .failed(error.localizedDescription) }
        }
    }

    private func exportCSV() -> URL? {
        var csv = "date,meal,source,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,items\n"
        let f = ISO8601DateFormatter()
        for m in meals {
            let items = m.items.sorted { $0.order < $1.order }
                .map { "\($0.name) \(FoodAnalyzer.trim($0.quantity)) \($0.unit)" }
                .joined(separator: "; ")
            func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            csv += [f.string(from: m.date), q(m.name), m.source.rawValue, "\(Int(m.calories.rounded()))", "\(Int(m.protein.rounded()))",
                    "\(Int(m.carbs.rounded()))", "\(Int(m.fat.rounded()))", "\(Int(m.fiber.rounded()))", "\(Int(m.sugar.rounded()))",
                    "\(Int(m.sodium.rounded()))", q(items)].joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meals.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func reset() {
        try? context.delete(model: MealEntry.self)
        try? context.delete(model: SavedFood.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: Profile.self)
        try? context.save()
    }
}
