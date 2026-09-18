import SwiftUI
import SwiftData

/// Eight short steps. Every step writes straight into the profile so there is nothing to lose on the way.
struct OnboardingView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @State private var step = 0
    @State private var apiKey = ""
    @State private var provider: AIProvider = .current
    @State private var keyStatus: KeyStatus = .idle
    @State private var plan = NutritionMath.Plan(bmr: 0, tdee: 0, calories: 0, protein: 0, carbs: 0, fat: 0)
    @State private var showSources = false

    enum KeyStatus { case idle, checking, ok, failed(String) }

    private let stepCount = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                switch step {
                case 0: welcome
                case 1: aboutYou
                case 2: body_
                case 3: activity
                case 4: goal
                case 5: planView
                case 6: keyStep
                default: health
                }
            }
            .id(step)
            .transition(.push(from: .trailing))
            .animation(.snappy(duration: 0.3), value: step)
            footer
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: step) { _, s in if s == 5 { profile.recalculateTargets(); plan = NutritionMath.plan(for: profile.inputs) } }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if step > 0 {
                    Button { step -= 1 } label: { Image(systemName: "chevron.left").font(.headline) }
                        .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(height: 24)
            ProgressView(value: Double(step + 1), total: Double(stepCount))
                .tint(.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var footer: some View {
        Button {
            if step == 6 && !apiKey.isEmpty { Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keyAccount) }
            if step == stepCount - 1 { finish() } else { step += 1 }
        } label: {
            Text(step == stepCount - 1 ? "Start tracking" : (step == 6 && apiKey.isEmpty ? "Skip for now" : "Continue"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(20)
    }

    private func finish() {
        profile.recalculateTargets()
        profile.onboarded = true
        context.insert(WeightEntry(weightKg: profile.weightKg))
        try? context.save()
        if profile.writeToHealth {
            Task { await HealthStore.shared.requestAuthorization() }
        }
    }

    // MARK: Steps

    private func page<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.largeTitle.weight(.bold))
                    Text(subtitle).font(.body).foregroundStyle(.secondary)
                }
                content()
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var welcome: some View {
        page("Plate", "Point your camera at a meal and log it in seconds. Your data stays on your phone and in Apple Health.") {
            VStack(alignment: .leading, spacing: 14) {
                feature("camera.fill", "Photo logging", "One photo becomes a list of foods with portions you can adjust.")
                feature("barcode.viewfinder", "Barcodes and labels", "Packaged food from Open Food Facts, or read the label itself.")
                feature("text.bubble.fill", "Describe it", "Type \"two eggs, toast with butter, black coffee\".")
                feature("heart.fill", "Apple Health", "Calories and macros written to Health. Steps and workouts read back.")
                feature("scalemass.fill", "Reality check", "After two weeks, Plate compares the scale to your log and corrects your target.")
            }
            .card()
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var aboutYou: some View {
        page("About you", "Used only for the calorie math. Nothing is uploaded.") {
            VStack(spacing: 12) {
                Picker("Units", selection: $profile.units) {
                    ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Sex", selection: $profile.sex) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Birth year")
                    Spacer()
                    Picker("Birth year", selection: $profile.birthYear) {
                        ForEach((1930...Calendar.current.component(.year, from: Date()) - 13).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .card()
        }
    }

    private var body_: some View {
        page("Height and weight", "Your current numbers. You can log new weights any time.") {
            VStack(spacing: 16) {
                HeightField(profile: profile)
                Divider()
                WeightField(title: "Weight", kg: $profile.weightKg, units: profile.units)
            }
            .card()
        }
    }

    private var activity: some View {
        page("Activity", "Pick the level that matches a normal week. Most people overestimate; when in doubt, go one lower.") {
            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        profile.activity = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.label).font(.subheadline.weight(.semibold))
                                Text(level.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: profile.activity == level ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(profile.activity == level ? Color.accentColor : Color.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var goal: some View {
        page("Goal", "Lose, keep, or gain. The pace sets how big the daily deficit or surplus is.") {
            VStack(spacing: 16) {
                Picker("Goal", selection: goalBinding) {
                    ForEach(Goal.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if profile.goal != .maintain {
                    WeightField(title: "Target weight", kg: $profile.targetWeightKg, units: profile.units)
                        .id(profile.goal)
                    PaceSlider(profile: profile)
                }
            }
            .card()
        }
    }

    private var goalBinding: Binding<Goal> {
        Binding(get: { profile.goal }, set: { g in
            profile.goal = g
            if g == .maintain { profile.targetWeightKg = profile.weightKg }
            else if g == .lose && profile.targetWeightKg >= profile.weightKg { profile.targetWeightKg = profile.weightKg - 5 }
            else if g == .gain && profile.targetWeightKg <= profile.weightKg { profile.targetWeightKg = profile.weightKg + 5 }
        })
    }

    private var planView: some View {
        page("Your plan", "Mifflin-St Jeor resting energy times your activity level, then the pace you picked. You can edit any of these later.") {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Daily calories").font(.footnote).foregroundStyle(.secondary)
                        Text("\(plan.calories)").font(.system(size: 44, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Resting \(plan.bmr)").font(.footnote).foregroundStyle(.secondary)
                        Text("Maintenance \(plan.tdee)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Divider()
                macroRow("Protein", plan.protein, .protein)
                macroRow("Carbs", plan.carbs, .carbs)
                macroRow("Fat", plan.fat, .fat)
                if let weeks = NutritionMath.weeksToGoal(profile.inputs, targetKg: profile.targetWeightKg) {
                    Divider()
                    let date = Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: Date())!
                    Label("Reach \(Units.weightString(profile.targetWeightKg, profile.units, decimals: 0)) around \(date.formatted(.dateTime.month(.wide).day()))", systemImage: "flag.checkered")
                        .font(.subheadline)
                }
                Divider()
                Button { showSources = true } label: {
                    Label("How these numbers are calculated, with sources", systemImage: "book")
                        .font(.footnote)
                }
            }
            .card()
        }
        .sheet(isPresented: $showSources) { NavigationStack { SourcesView() } }
    }

    private func macroRow(_ name: String, _ grams: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(name)
            Spacer()
            Text("\(grams) g").monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var keyStep: some View {
        page("Photo logging", "Plate sends meal photos to a hosted model for the estimate. Pick a provider and paste its API key to turn that on. Barcodes, search, and manual entry work without it.") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { _, p in AIProvider.current = p; apiKey = Keychain.get(p.keyAccount) ?? ""; keyStatus = .idle }
                SecureField(provider.keyPlaceholder, text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("Test key") { testKey() }
                        .disabled(apiKey.isEmpty)
                    Spacer()
                    switch keyStatus {
                    case .idle: EmptyView()
                    case .checking: ProgressView()
                    case .ok: Label("Works", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let why): Text(why).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
                .font(.subheadline)
                Text("\(provider.consoleHint) Keys are stored in the iOS keychain and only ever sent to \(provider.host).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func testKey() {
        keyStatus = .checking
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(key, for: provider.keyAccount)
        Task {
            do {
                try await AIClient(provider: provider).verifyKey()
                keyStatus = .ok
            } catch {
                keyStatus = .failed(error.localizedDescription)
            }
        }
    }

    private var health: some View {
        page("Apple Health", "Plate can write every meal to Health and read your steps, workouts, and weight back.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Sync with Apple Health", isOn: $profile.writeToHealth)
                Toggle("Add workout calories to my target", isOn: $profile.addExerciseCalories)
                Text("Adds active energy from Health to the day's budget. Watches overcount, so many people leave this off.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Roll unused calories into tomorrow", isOn: $profile.rolloverCalories)
                Text("Up to 250 kcal from yesterday.").font(.footnote).foregroundStyle(.secondary)
            }
            .card()
        }
    }
}

struct HeightField: View {
    @Bindable var profile: Profile
    @State private var feet: Int
    @State private var inches: Int

    init(profile: Profile) {
        self.profile = profile
        let (f, i) = Units.cmToFeetInches(profile.heightCm)
        self._feet = State(initialValue: f)
        self._inches = State(initialValue: i)
    }

    var body: some View {
        HStack {
            Text("Height")
            Spacer()
            if profile.units == .metric {
                NumberField(title: "cm", value: $profile.heightCm).frame(width: 70)
                Text("cm").foregroundStyle(.secondary)
            } else {
                Picker("ft", selection: $feet) { ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) } }.labelsHidden()
                Picker("in", selection: $inches) { ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) } }.labelsHidden()
            }
        }
        .onChange(of: feet) { _, _ in profile.heightCm = Units.feetInchesToCm(feet, inches) }
        .onChange(of: inches) { _, _ in profile.heightCm = Units.feetInchesToCm(feet, inches) }
    }
}

struct WeightField: View {
    var title: String
    @Binding var kg: Double
    var units: UnitSystem
    @State private var shown: Double

    init(title: String, kg: Binding<Double>, units: UnitSystem) {
        self.title = title
        self._kg = kg
        self.units = units
        self._shown = State(initialValue: units == .metric ? kg.wrappedValue : Units.kgToLb(kg.wrappedValue))
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            NumberField(title: units == .metric ? "kg" : "lb", value: $shown, decimals: 1).frame(width: 80)
            Text(units == .metric ? "kg" : "lb").foregroundStyle(.secondary)
        }
        .onAppear { shown = units == .metric ? kg : Units.kgToLb(kg) }
        .onChange(of: units) { _, u in shown = u == .metric ? kg : Units.kgToLb(kg) }
        .onChange(of: shown) { _, v in
            let newKg = units == .metric ? v : Units.lbToKg(v)
            if abs(newKg - kg) > 0.01 { kg = newKg }
        }
        .onChange(of: kg) { _, k in
            let expected = units == .metric ? k : Units.kgToLb(k)
            if abs(expected - shown) > 0.05 { shown = expected }
        }
    }
}

struct PaceSlider: View {
    @Bindable var profile: Profile

    private var paceLabel: String {
        profile.units == .metric
            ? String(format: "%.2f kg per week", profile.paceKgPerWeek)
            : String(format: "%.1f lb per week", Units.kgToLb(profile.paceKgPerWeek))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pace").font(.subheadline)
                Spacer()
                Text(paceLabel).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Slider(value: $profile.paceKgPerWeek, in: 0.1...1.0, step: 0.05)
            HStack {
                Text("Gentle").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(hint).font(.caption).foregroundStyle(profile.paceKgPerWeek > 0.75 ? .orange : .secondary)
                Spacer()
                Text("Aggressive").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var hint: String {
        switch profile.paceKgPerWeek {
        case ..<0.3: return "Easy to stick to"
        case ..<0.6: return "Recommended"
        case ..<0.8: return "Hard but doable"
        default: return "Hunger and muscle loss likely"
        }
    }
}
