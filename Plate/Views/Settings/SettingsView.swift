import SwiftData
import SwiftUI

/// Everything the plan is built from, all editable. Changing an answer here offers to rebuild the
/// targets rather than doing it behind your back, because a number you set on purpose should stay
/// where you put it.
struct SettingsView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @State private var provider: AIProvider = .current
    @State private var apiKey = Keychain.get(AIProvider.current.keyAccount) ?? ""
    @AppStorage(ClaudeClient.modelDefaultsKey) private var model = ClaudeClient.defaultModel
    /// Off until someone asks for it, so an app with no wearable behaves exactly as it always has.
    @AppStorage(HealthSignals.defaultsKey) private var readWearable = false
    @StateObject private var health = HealthStore.shared
    @State private var keyStatus: APIKeyStatus = .idle
    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var showAvoidSheet = false
    @State private var showRefine = false
    @State private var newAvoid = ""

    /// True when an answer has changed since the targets were last worked out.
    private var targetsAreStale: Bool {
        let fresh = profile.plan
        return fresh.calories != profile.calorieTarget || fresh.protein != profile.proteinTarget
    }

    var body: some View {
        NavigationStack {
            Form {
                planSection
                targetsSection
                bodySection
                movementSection
                goalSection
                eatingSection
                focusSection
                daySection
                healthSection
                analysisSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all meals, weights, measurements, and your profile?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { reset() }
            }
            .sheet(isPresented: $showAvoidSheet) { avoidSheet }
            // The same flow onboarding uses, opened at the plan so only the optional runs are on
            // offer. Answers written here are the same answers, so nothing is duplicated.
            .fullScreenCover(isPresented: $showRefine) {
                OnboardingView(profile: profile, mode: .refinement) { showRefine = false }
            }
        }
    }

    // MARK: Plan

    private var planSection: some View {
        Section {
            NavigationLink { PlanView(profile: profile) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.clipboard.fill")
                        .foregroundStyle(Color.accentColor).font(.title3).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your plan").font(.subheadline.weight(.semibold))
                        Text("\(profile.calorieTarget) kcal, \(profile.proteinTarget) g protein, and the working behind it")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if targetsAreStale {
                Button {
                    withAnimation { profile.recalculateTargets() }
                } label: {
                    Label("Your answers changed. Rebuild the targets", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
            }
            Button {
                showRefine = true
            } label: {
                Label("Make your plan sharper", systemImage: "sparkles")
                    .font(.subheadline)
            }
            Button {
                profile.onboarded = false
            } label: {
                Label("Answer the setup questions again", systemImage: "text.badge.checkmark")
                    .font(.subheadline)
            }
        } footer: {
            Text("The optional questions sharpen one number each. You can answer a part at a time and stop whenever you like.")
        }
    }

    // MARK: Targets

    private var targetsSection: some View {
        Section {
            intRow("Calories", $profile.calorieTarget, "kcal")
            intRow("Protein", $profile.proteinTarget, "g")
            intRow("Carbs", $profile.carbTarget, "g")
            intRow("Fat", $profile.fatTarget, "g")
            intRow("Fiber", $profile.fiberTarget, "g")
            intRow("Water", $profile.waterMl, "ml")
            Button("Recalculate from my answers") { profile.recalculateTargets() }
        } header: {
            Text("Targets")
        } footer: {
            Text("Editing a number by hand leaves the others alone. Recalculate to get a matching set.")
        }
    }

    // MARK: You

    private var bodySection: some View {
        Section("You") {
            Picker("Units", selection: $profile.units) {
                ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Sex", selection: $profile.sex) {
                ForEach(Sex.allCases) { Text($0.label).tag($0) }
            }
            DatePicker("Date of birth",
                       selection: Binding(get: { profile.birthDate ?? defaultBirthDate },
                                          set: {
                                              profile.birthDate = $0
                                              profile.birthYear = Calendar.current.component(.year, from: $0)
                                          }),
                       in: ...Date(), displayedComponents: .date)
            HeightField(profile: profile)
            WeightField(title: "Weight", kg: $profile.weightKg, units: profile.units)
            NavigationLink("Measurements and body fat") { BodyView(profile: profile) }
        }
    }

    private var defaultBirthDate: Date {
        Calendar.current.date(from: DateComponents(year: profile.birthYear, month: 6, day: 15)) ?? Date()
    }

    // MARK: Movement

    private var movementSection: some View {
        Section {
            Picker("Everyday movement", selection: Binding(
                get: { profile.dailyActivity ?? .light },
                set: { profile.dailyActivity = $0 })) {
                    ForEach(DailyActivity.allCases) { Text($0.label).tag($0) }
                }
            Picker("Training", selection: $profile.trainingStyle) {
                ForEach(TrainingStyle.allCases) { Text($0.label).tag($0) }
            }
            if profile.trainingStyle != .none {
                Stepper("Days a week: \(profile.trainingDaysPerWeek)",
                        value: $profile.trainingDaysPerWeek, in: 0...7)
                Stepper("Session length: \(profile.trainingMinutes) min",
                        value: $profile.trainingMinutes, in: 15...150, step: 15)
                Picker("Experience", selection: $profile.experience) {
                    ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
                }
            }
        } header: {
            Text("Movement")
        } footer: {
            let burn = Int(NutritionMath.trainingKcalPerDay(profile.inputs).rounded())
            Text(burn > 0
                 ? "Everyday movement and training are counted separately so neither is double counted. Your training adds about \(burn) calories a day across the week."
                 : "Everyday movement is life outside workouts. Training is asked separately so neither is double counted.")
        }
    }

    // MARK: Goal

    private var goalSection: some View {
        Section {
            Picker("Goal", selection: $profile.goal) {
                ForEach(Goal.allCases) { Text($0.label).tag($0) }
            }
            if profile.goal.changesWeight {
                WeightField(title: "Target weight", kg: $profile.targetWeightKg, units: profile.units)
                PaceSlider(profile: profile)
            }
            if profile.bodyFat != nil {
                HStack {
                    Text("Target body fat")
                    Spacer()
                    if let target = profile.targetBodyFat {
                        Text("\(Int(target.rounded())) %").foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("Not set").foregroundStyle(.tertiary)
                    }
                }
                Slider(value: Binding(get: { profile.targetBodyFat ?? (profile.bodyFat?.percent ?? 20) },
                                      set: { profile.targetBodyFat = $0 }),
                       in: BodyComposition.healthyFloor(for: profile.sex)...50, step: 1)
            }
            Picker("Calorie split", selection: $profile.cycling) {
                ForEach(CalorieCycling.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Goal")
        } footer: {
            Text(profile.goal.detail)
        }
    }

    // MARK: Eating

    private var eatingSection: some View {
        Section {
            Picker("Diet", selection: $profile.diet) {
                ForEach(DietStyle.allCases) { Text($0.label).tag($0) }
            }
            Picker("Meals a day", selection: $profile.mealPattern) {
                ForEach(MealPattern.allCases) { Text($0.label).tag($0) }
            }
            Stepper("Drinks a week: \(profile.drinksPerWeek)", value: $profile.drinksPerWeek, in: 0...40)
            Button {
                showAvoidSheet = true
            } label: {
                HStack {
                    Text("Foods to avoid").foregroundStyle(.primary)
                    Spacer()
                    Text(profile.avoids.isEmpty ? "None" : profile.avoids.joined(separator: ", "))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } header: {
            Text("Eating")
        } footer: {
            Text(profile.diet.detail)
        }
    }

    private var avoidSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add a food", text: $newAvoid)
                            .autocorrectionDisabled()
                            .onSubmit(addAvoid)
                        Button("Add", action: addAvoid)
                            .disabled(newAvoid.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !profile.avoids.isEmpty {
                    Section("Avoiding") {
                        ForEach(profile.avoids, id: \.self) { Text($0) }
                            .onDelete { offsets in
                                var list = profile.avoids
                                list.remove(atOffsets: offsets)
                                profile.avoids = list
                            }
                    }
                }
                Section {
                    Text("These are given to the photo analyzer so it does not guess a food you never eat.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Foods to avoid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAvoidSheet = false } } }
        }
    }

    private func addAvoid() {
        let value = newAvoid.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        var list = profile.avoids
        if !list.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { list.append(value) }
        profile.avoids = list
        newAvoid = ""
    }

    // MARK: Focus areas

    private var focusSection: some View {
        Section {
            ForEach(BodyArea.allCases) { area in
                Button {
                    toggle(area)
                } label: {
                    HStack {
                        Image(systemName: area.symbol).frame(width: 24).foregroundStyle(Color.accentColor)
                        Text(area.label).foregroundStyle(.primary)
                        Spacer()
                        if profile.focusAreas.contains(area) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            if !profile.focusAreas.isEmpty {
                Picker("What you want there", selection: $profile.areaGoal) {
                    ForEach(AreaGoal.allCases) { Text($0.label).tag($0) }
                }
            }
        } header: {
            Text("Focus areas")
        } footer: {
            Text(FocusGuidance.spotReductionNote)
        }
    }

    private func toggle(_ area: BodyArea) {
        var list = profile.focusAreas
        if let index = list.firstIndex(of: area) { list.remove(at: index) } else { list.append(area) }
        profile.focusAreas = list
    }

    // MARK: Day, Health, analysis, data

    private var daySection: some View {
        Section("Daily budget") {
            Toggle("Add workout calories", isOn: $profile.addExerciseCalories)
            Toggle("Roll over unused calories", isOn: $profile.rolloverCalories)
            Toggle("Show the Body tab", isOn: $profile.showBodyTab)
        }
    }

    private var healthSection: some View {
        Section {
            Toggle("Sync with Apple Health", isOn: $profile.writeToHealth)
                .onChange(of: profile.writeToHealth) { _, on in
                    if on { Task { await HealthStore.shared.requestAuthorization() } }
                }
            Button("Import latest weight from Health") {
                Task {
                    if let (date, kg) = await HealthStore.shared.latestWeight() {
                        context.insert(WeightEntry(date: date, weightKg: kg, fromHealth: true))
                        profile.weightKg = kg
                    }
                }
            }
            .disabled(!profile.writeToHealth)

            // Asked for here and nowhere else, so nobody meets a permission sheet at launch for a
            // feature they have not turned on.
            Toggle("Read my wearable", isOn: $readWearable)
                .onChange(of: readWearable) { _, on in
                    if on {
                        Task {
                            await HealthStore.shared.requestSignalAuthorization()
                            await refreshSignals()
                        }
                    } else {
                        HealthStore.shared.signals = HealthSignals.Snapshot()
                    }
                }
            if readWearable {
                NavigationLink {
                    HealthSignalsView(profile: profile)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What Health knows")
                        Text(wearableSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // Read again whenever this row comes back on screen, so a fresh launch shows what
                // is there rather than waiting to be asked.
                .task { await refreshSignals() }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Meals are written as dietary energy, protein, carbs, fat, fiber, sugar, and sodium. Editing or deleting a meal updates Health. A Whoop, an Apple Watch or anything else that writes into Health can fill in your burn, your workouts, and your sleep and heart rate as context. Whole days only, and one source at a time so two devices are never counted twice.")
        }
    }

    /// What was last read, so the switch is visibly doing something. Silence when a wearable is
    /// absent is the correct answer and this says so plainly rather than leaving a blank row.
    private var wearableSummary: String {
        let signals = health.signals
        if let burn = signals.burn {
            return "\(burn.tdee) kcal a day from \(burn.source.label), over \(burn.days) days"
        }
        if let sleep = signals.recovery.sleepSource ?? signals.recovery.restingHeartRateSource {
            return "Sleep and heart rate from \(sleep.label)"
        }
        if let workout = signals.workouts.first {
            return "Workouts from \(workout.source.label)"
        }
        return signals.readAt == nil ? "Checking" : "Nothing written by a wearable yet"
    }

    private func refreshSignals() async {
        await HealthStore.shared.refreshSignals(prediction: HealthSignals.Prediction(profile.inputs))
    }

    @ViewBuilder private var analysisSection: some View {
        Section {
            Picker("Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, p in
                AIProvider.current = p
                apiKey = Keychain.get(p.keyAccount) ?? ""
                keyStatus = .idle
            }
            SecureField(provider.keyPlaceholder, text: $apiKey)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onChange(of: apiKey) { _, k in
                    Keychain.set(k.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keyAccount)
                    keyStatus = .idle
                }
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
            if provider == .gemini, let active = GeminiClient.rememberedModel {
                LabeledContent("Model in use", value: active)
            }
            if provider == .anthropic {
                Picker("Model", selection: $model) {
                    ForEach(ClaudeClient.models, id: \.id) { m in
                        VStack(alignment: .leading) {
                            Text(m.label)
                            Text(m.note).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(m.id)
                    }
                }
                .pickerStyle(.inline)
            }
        } header: {
            Text("Photo analysis")
        } footer: {
            Text("\(provider.consoleHint) Needed for photo, label, and description logging. Stored in the keychain, sent only to \(provider.host). Barcodes and search use Open Food Facts and need no key.")
        }

        spendSection
    }

    /// What the scanning has actually cost. A scan is fractions of a cent, which is small enough to
    /// feel like nothing and add up anyway, so the running total is on screen rather than waiting on
    /// a bill at the end of the month.
    @ViewBuilder private var spendSection: some View {
        let usage = AIUsage.summary
        if usage.scans > 0 {
            Section {
                LabeledContent("Scans", value: "\(usage.scans)")
                LabeledContent("Spent", value: usage.dollars < 0.01
                               ? "under a cent"
                               : String(format: "$%.2f", usage.dollars))
                if let perDollar = usage.scansPerDollar {
                    LabeledContent("A dollar buys", value: "about \(perDollar) more")
                }
                Button("Reset the count") { AIUsage.reset() }
            } header: {
                Text("What it has cost")
            } footer: {
                if let since = usage.since {
                    Text("Counted from \(since.formatted(date: .abbreviated, time: .omitted)) using published token prices, so treat it as close rather than exact. Your provider's own dashboard is the real bill.")
                }
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share meals.csv", systemImage: "square.and.arrow.up") }
            } else {
                Button("Export meals as CSV", systemImage: "tablecells") { exportURL = exportCSV() }
            }
            Button("Reset everything", systemImage: "trash", role: .destructive) { confirmReset = true }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            Link("Source on GitHub", destination: URL(string: "https://github.com/Dunebru/plate")!)
            Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
            NavigationLink("Sources and medical disclaimer") { SourcesView() }
            Text("Estimates from a photo are typically within 10 to 30 percent. Check the portions, correct what is wrong, and trust the weekly trend over any single number.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func intRow(_ label: String, _ value: Binding<Int>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            NumberField(title: "0", value: Binding(get: { Double(value.wrappedValue) },
                                                   set: {
                                                       value.wrappedValue = Int($0)
                                                       profile.targetsEditedByUser = true
                                                   }))
                .frame(width: 80)
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
        try? context.delete(model: BodyMeasurement.self)
        try? context.delete(model: Profile.self)
        try? context.save()
    }
}
