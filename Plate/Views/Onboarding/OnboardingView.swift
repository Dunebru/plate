import SwiftUI
import SwiftData

/// The questionnaire, in two halves.
///
/// The first half asks only what a calorie and macro target is actually built from: what you want,
/// who you are, how big you are, how much you move, and how fast you want to go. That is enough to
/// finish, so the plan arrives in eight screens and the profile is marked done the moment it does.
///
/// The second half is optional and comes in named runs. Each one says what it sharpens before it
/// starts, and hands you back to an updated plan when it ends, so you can stop after any of them.
struct OnboardingView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context

    /// Where this was opened from. The full run starts at the welcome screen and ends with someone
    /// set up. The refinement run starts at the plan and offers only the optional questions, which
    /// is what the Settings entry point wants.
    enum Mode { case full, refinement }

    let mode: Mode
    let onFinish: () -> Void

    init(profile: Profile, mode: Mode = .full, onFinish: @escaping () -> Void = {}) {
        _profile = Bindable(wrappedValue: profile)
        self.mode = mode
        self.onFinish = onFinish
        _step = State(initialValue: mode == .refinement ? .plan : .welcome)
        _leg = State(initialValue: mode == .refinement ? .hub : .essentials)
    }

    enum Step: Int, CaseIterable {
        // Phase one. Nothing here can be skipped, because nothing here can be guessed.
        case welcome, goal, basics, size, movement, targetWeight, pace, generating, plan
        // Phase two, one named run at a time. Each opens with its own intro screen.
        case trainingIntro, trainingStyle, trainingLoad, experience
        case bodyFatIntro, tape, targetBodyFat
        case eatingIntro, diet, avoids, mealPattern, cycling
        case habitsIntro, focus, drinks, obstacles
        case setupIntro, health, apiKey

        /// Phase one in order. Everything below it in the enum refines a number that already exists.
        static let essentials: [Step] = [.welcome, .goal, .basics, .size, .movement,
                                         .targetWeight, .pace, .generating, .plan]
    }

    /// A named run of optional questions. It says what it buys before it starts, says how long it
    /// is, and ends back at the plan, so no run is ever open ended.
    struct Chunk: Identifiable {
        struct Gain: Identifiable {
            var symbol: String
            var title: String
            var detail: String
            var id: String { title }
        }

        var id: String
        var title: String
        var symbol: String
        /// One line for the list on the plan screen: what answering this buys.
        var promise: String
        var heading: String
        var blurb: String
        var gains: [Gain]
        var note: String? = nil
        var startTitle: String = "Answer them"
        /// The intro screen first, then the questions.
        var steps: [Step]
    }

    static let chunks: [Chunk] = [
        Chunk(id: "training",
              title: "Training",
              symbol: "dumbbell.fill",
              promise: "Sharpens the daily burn your target is built on",
              heading: "What your training costs",
              blurb: "Three questions. Until they are answered your target assumes you do nothing on purpose, so every session you do is missing from it.",
              gains: [
                .init(symbol: "flame.fill", title: "Sessions go into the budget",
                      detail: "What a workout costs is worked out from your weight and the kind of training, then spread across the week."),
                .init(symbol: "speedometer", title: "A gaining plan gets a ceiling",
                      detail: "How long you have trained sets how fast muscle can arrive, and that is what caps a surplus."),
              ],
              steps: [.trainingIntro, .trainingStyle, .trainingLoad, .experience]),
        Chunk(id: "bodyFat",
              title: "Body fat",
              symbol: "ruler",
              promise: "Swaps the resting burn formula for one built on your lean mass",
              heading: "Three measurements, one real number",
              blurb: "A tape round your neck and waist turns a guess into a body fat figure within about three points of a DEXA scan. It takes a minute.",
              gains: [
                .init(symbol: "flame.fill", title: "A better resting burn",
                      detail: "Lean mass predicts resting energy better than weight does, so the whole plan sharpens."),
                .init(symbol: "fork.knife", title: "Protein against lean mass",
                      detail: "Fat does not need feeding. Protein is set from the muscle you actually carry."),
                .init(symbol: "speedometer", title: "A safe pace for your level",
                      detail: "How fast you can lose depends on how much fat there is to lose."),
              ],
              note: "Skip it if you have no tape to hand. Plate falls back to a BMI estimate and says so wherever it shows the number.",
              startTitle: "Take three measurements",
              steps: [.bodyFatIntro, .tape, .targetBodyFat]),
        Chunk(id: "eating",
              title: "How you eat",
              symbol: "fork.knife",
              promise: "Shapes your macros and how the day is split",
              heading: "How you like to eat",
              blurb: "Four questions. None of them change the calorie total. They change how it splits into protein, carbs and fat, and how it is spread across the day and the week.",
              gains: [
                .init(symbol: "chart.pie.fill", title: "Macros that match your plate",
                      detail: "A low carb or plant based week needs a different split to land the same protein."),
                .init(symbol: "calendar", title: "Days that are not all the same",
                      detail: "Eat more when you train or at the weekend, with the weekly total unchanged."),
              ],
              steps: [.eatingIntro, .diet, .avoids, .mealPattern, .cycling]),
        Chunk(id: "habits",
              title: "Habits",
              symbol: "lightbulb.fill",
              promise: "Picks the guidance and nudges Plate shows you",
              heading: "What you want, and what gets in the way",
              blurb: "Three questions. None of them move the calorie number. They decide which advice you see and when.",
              gains: [
                .init(symbol: "figure.strengthtraining.traditional", title: "Guidance for the parts you care about",
                      detail: "Honest advice per body part, including what training can and cannot change."),
                .init(symbol: "wineglass", title: "Drinks counted properly",
                      detail: "Alcohol carries calories with almost nothing useful attached, and it is the easiest thing to forget."),
              ],
              steps: [.habitsIntro, .focus, .drinks, .obstacles]),
        Chunk(id: "setup",
              title: "Setup",
              symbol: "gearshape.fill",
              promise: "Turns on Apple Health and logging from a photo",
              heading: "Health and photo logging",
              blurb: "Two screens. Neither moves your target, both decide how much typing you do.",
              gains: [
                .init(symbol: "heart.fill", title: "Apple Health, both ways",
                      detail: "Meals go out as they are logged. Weight and workouts come back in, so you only type things once."),
                .init(symbol: "camera.fill", title: "Photograph a meal",
                      detail: "A key from a hosted model turns on logging from a photo. Barcodes, search and manual entry work without one."),
              ],
              steps: [.setupIntro, .health, .apiKey]),
    ]

    /// Which run of screens is on. The plan belongs to the essential run while it is being revealed,
    /// and to the hub once an optional run has handed it back.
    private enum Leg: Equatable {
        case essentials
        case chunk(String)
        case hub
    }

    @State private var step: Step
    @State private var leg: Leg
    @State private var movingForward = true
    @State private var answered: Set<Step> = []
    @State private var goalChoices: Set<GoalChoice> = []
    @State private var sexTouched = false
    @State private var dobTouched = false
    @State private var targetWeightTouched = false
    @State private var doneChunks: Set<String> = []
    @State private var lastChunk: Chunk?
    @State private var planBefore: NutritionMath.Plan?
    @State private var selectionTick = 0
    @State private var revealTick = 0
    @State private var newAvoid = ""
    @State private var apiKey = ""
    @State private var provider: AIProvider = .current
    @State private var keyStatus: APIKeyStatus = .idle
    @State private var plan = NutritionMath.Plan(bmr: 0, tdee: 0, calories: 0, protein: 0, carbs: 0, fat: 0)
    @State private var showSources = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .id(step)
                .transition(.push(from: movingForward ? .trailing : .leading))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sensoryFeedback(.success, trigger: revealTick)
        .sheet(isPresented: $showSources) { NavigationStack { SourcesView() } }
        .onAppear(perform: seedAnswers)
        .onChange(of: step) { _, now in
            guard now == .plan else { return }
            arriveAtPlan()
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Back")
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)

            FlowProgressBar(progress: progress)

            Text(counterLabel)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
        // Kept in the layout rather than removed, so the question below it does not jump.
        .opacity(showsProgress ? 1 : 0)
        .disabled(!showsProgress)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            switch step {
            case .generating:
                EmptyView()
            case .trainingIntro, .bodyFatIntro, .eatingIntro, .habitsIntro, .setupIntro:
                Button(chunk?.startTitle ?? "Answer them") { advance() }
                    .buttonStyle(FlowButtonStyle())
                Button("Skip this part") { skipChunk() }
                    .buttonStyle(FlowButtonStyle(prominent: false))
            case .plan:
                Button(mode == .refinement ? "Done" : "Start tracking") { leave() }
                    .buttonStyle(FlowButtonStyle())
                if let next = nextChunk {
                    Button("Make it sharper") { start(next) }
                        .buttonStyle(FlowButtonStyle(prominent: false))
                }
            default:
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(FlowButtonStyle())
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.35)
                    .animation(.flow, value: canContinue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .tape: return tapeBodyFat == nil ? "Skip for now" : "Continue"
        case .focus: return profile.focusAreas.isEmpty ? "Nowhere in particular" : "Continue"
        case .avoids: return profile.avoids.isEmpty ? "Nothing to avoid" : "Continue"
        case .obstacles: return profile.obstacles.isEmpty ? "Skip" : "Continue"
        case .apiKey: return apiKey.trimmed.isEmpty ? "Skip for now" : "Continue"
        default: return "Continue"
        }
    }

    private func primaryAction() {
        if step == .apiKey, !apiKey.trimmed.isEmpty {
            Keychain.set(apiKey.trimmed, for: provider.keyAccount)
        }
        advance()
    }

    private var canContinue: Bool {
        switch step {
        case .basics: return sexTouched && dobTouched
        case .goal: return Goal.from(goalChoices) != nil
        case .movement, .trainingStyle, .experience, .diet, .mealPattern, .cycling:
            return answered.contains(step)
        case .trainingLoad: return profile.trainingDaysPerWeek > 0
        default: return true
        }
    }

    // MARK: Where we are

    private var chunk: Chunk? {
        guard case .chunk(let id) = leg else { return nil }
        return Self.chunks.first { $0.id == id }
    }

    private var nextChunk: Chunk? { Self.chunks.first { !doneChunks.contains($0.id) } }

    /// Every screen on this run, in the order they are walked.
    private var route: [Step] {
        switch leg {
        case .essentials: return Step.essentials.filter(applies)
        case .hub: return [.plan]
        case .chunk: return ((chunk?.steps ?? []) + [.plan]).filter(applies)
        }
    }

    /// What the counter is allowed to count. The title card and the working it out screen are not
    /// questions, and the plan is the reward at the end of an optional run rather than a part of
    /// it, so none of the three are counted.
    private var counted: [Step] {
        route.filter { $0 != .welcome && $0 != .generating && !($0 == .plan && chunk != nil) }
    }

    private func applies(_ candidate: Step) -> Bool {
        switch candidate {
        case .trainingLoad, .experience: return profile.trainingStyle != .none
        case .targetWeight, .pace: return profile.goal.changesWeight
        case .targetBodyFat: return (tapeBodyFat ?? 0) > bodyFatFloor + 1
        default: return true
        }
    }

    private var shownIndex: Int { counted.firstIndex(of: step) ?? 0 }

    private var progress: Double {
        counted.isEmpty ? 0 : Double(shownIndex + 1) / Double(counted.count)
    }

    private var counterLabel: String {
        let position = "\(shownIndex + 1) of \(counted.count)"
        guard let chunk else { return position }
        return "\(chunk.title) · \(position)"
    }

    private var showsProgress: Bool {
        counted.count > 1 && counted.contains(step)
    }

    private var canGoBack: Bool {
        if step == .generating || leg == .hub { return false }
        // The first screen of an optional run goes back to the plan, so no run is ever a trap.
        if chunk != nil { return true }
        return step != .welcome
    }

    private func advance() {
        // The goal is asked before the scale reading now, so the target weight it implies can only
        // be worked out once height and weight are in.
        if step == .size { applyGoalDefaults() }
        let path = route
        guard let index = path.firstIndex(of: step), index + 1 < path.count else { return }
        let next = path[index + 1]
        if next == .plan, let chunk {
            completeChunk(chunk)
            goToPlan(forward: true)
            return
        }
        go(to: next, forward: true)
    }

    private func back() {
        let path = route.filter { $0 != .generating }
        guard let index = path.firstIndex(of: step) else { return }
        guard index > 0 else {
            if chunk != nil { goToPlan(forward: false) }
            return
        }
        go(to: path[index - 1], forward: false)
    }

    private func go(to next: Step, forward: Bool) {
        withAnimation(.flow) {
            movingForward = forward
            step = next
        }
    }

    private func goToPlan(forward: Bool) {
        withAnimation(.flow) {
            movingForward = forward
            leg = .hub
            step = .plan
        }
    }

    /// A choice was made: animate the fill, remember it, tap the taptic engine.
    private func pick(_ change: () -> Void) {
        withAnimation(.flow) { change() }
        answered.insert(step)
        selectionTick += 1
    }

    private func seedAnswers() {
        // A profile with a birthday on it has been through setup before, so its answers are shown
        // as given rather than asked for from scratch.
        if profile.birthDate != nil {
            sexTouched = true
            dobTouched = true
            targetWeightTouched = true
            goalChoices = profile.goal.choices
        }
        if profile.dailyActivity != nil { answered.insert(.movement) }
        apiKey = Keychain.get(provider.keyAccount) ?? ""
        plan = profile.plan
    }

    // MARK: Optional runs

    private func start(_ chunk: Chunk) {
        planBefore = profile.plan
        lastChunk = nil
        withAnimation(.flow) {
            movingForward = true
            leg = .chunk(chunk.id)
            step = chunk.steps[0]
        }
    }

    /// Leaves a run without answering it. Nothing is written, so the profile defaults stand and the
    /// targets are exactly what they were a screen ago.
    private func skipChunk() {
        selectionTick += 1
        goToPlan(forward: false)
    }

    private func completeChunk(_ chunk: Chunk) {
        doneChunks.insert(chunk.id)
        lastChunk = chunk
        if chunk.id == "bodyFat" { recordTapeMeasurement() }
    }

    /// The tape numbers live on the profile, but the Body screens chart measurements over time, so
    /// the first set is written as one too.
    private func recordTapeMeasurement() {
        guard profile.neckCm != nil || profile.waistCm != nil || profile.hipCm != nil else { return }
        let measurement = BodyMeasurement()
        measurement.weightKg = profile.weightKg
        measurement.neckCm = profile.neckCm
        measurement.waistCm = profile.waistCm
        measurement.hipCm = profile.hipCm
        measurement.refreshBodyFat(sex: profile.sex, heightCm: profile.heightCm,
                                   fallbackWeightKg: profile.weightKg)
        context.insert(measurement)
    }

    // MARK: Finishing

    private func arriveAtPlan() {
        // A target edited by hand in Settings is only overwritten once an answer behind it moved.
        if mode == .full || lastChunk != nil { profile.recalculateTargets() }
        plan = profile.plan
        revealTick += 1
        finishEssentials()
    }

    /// Phase one is everything the app needs, so it is committed the moment the plan appears.
    /// Someone who stops here is fully set up, and someone who carries on refining cannot lose it.
    private func finishEssentials() {
        guard mode == .full, !profile.onboarded else { return }
        profile.onboarded = true
        context.insert(WeightEntry(weightKg: profile.weightKg))
        try? context.save()
    }

    private func leave() {
        profile.onboarded = true
        try? context.save()
        if profile.writeToHealth {
            Task { await HealthStore.shared.requestAuthorization() }
        }
        onFinish()
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .goal: goalStep
        case .basics: basicsStep
        case .size: sizeStep
        case .movement: movementStep
        case .targetWeight: targetWeightStep
        case .pace: paceStep
        case .generating: generatingStep
        case .plan: planStep
        case .trainingIntro, .bodyFatIntro, .eatingIntro, .habitsIntro, .setupIntro: chunkIntroStep
        case .trainingStyle: trainingStyleStep
        case .trainingLoad: trainingLoadStep
        case .experience: experienceStep
        case .tape: tapeStep
        case .targetBodyFat: targetBodyFatStep
        case .focus: focusStep
        case .diet: dietStep
        case .avoids: avoidsStep
        case .mealPattern: mealPatternStep
        case .cycling: cyclingStep
        case .drinks: drinksStep
        case .obstacles: obstaclesStep
        case .health: healthStep
        case .apiKey: apiKeyStep
        }
    }

    // 1. Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            Text("Plate")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .padding(.top, 20)
            Text("A calorie number worked out for your body, and a camera that does the logging.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 18) {
                valueLine("camera.fill", "Photograph a meal, it is logged")
                valueLine("function", "Targets from your body, not a chart")
                valueLine("chart.xyaxis.line", "A trend line that ignores water weight")
                valueLine("lock.fill", "Everything stays on your phone")
            }
            .padding(.top, 36)
            Text("Six questions and your plan is ready.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 28)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
    }

    private func valueLine(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 2. Goal. Asked first, because it frames every question after it.

    private var goalStep: some View {
        OnboardingPage("What are you here for?",
                       "Tick everything that is true. Losing fat and building muscle at the same time is a real answer, so both boxes can be ticked at once.") {
            VStack(spacing: 12) {
                ForEach(GoalChoice.allCases) { option in
                    ChoiceRow(symbol: option.symbol,
                              label: option.label,
                              detail: option.detail,
                              selected: goalChoices.contains(option),
                              emphasis: true,
                              multiple: true) {
                        toggleGoal(option)
                    }
                }
                if Goal.from(goalChoices) == .recomp {
                    Callout(symbol: "arrow.triangle.swap",
                            text: "Both at once is what Plate calls a recomposition. You eat at about maintenance and train hard, so the scale barely moves while your shape does. It is slower than doing one at a time.",
                            tint: .accentColor)
                }
            }
        }
    }

    private func toggleGoal(_ choice: GoalChoice) {
        let chosen = Goal.toggling(choice, in: goalChoices)
        pick {
            goalChoices = chosen
            if let goal = Goal.from(chosen) { profile.goal = goal }
        }
    }

    // 3. Sex and date of birth. One screen, because they are the same question about your body.

    private var basicsStep: some View {
        OnboardingPage("What sex are you, and when were you born?",
                       "The resting burn and body fat formulas are calibrated separately by sex, and resting burn falls a little every year. Both move every number that follows.") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sex").font(.subheadline.weight(.semibold))
                    ForEach(Sex.allCases) { option in
                        ChoiceRow(symbol: option == .male ? "figure.stand" : "figure.stand.dress",
                                  label: option.label,
                                  selected: sexTouched && profile.sex == option) {
                            pick {
                                profile.sex = option
                                sexTouched = true
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Date of birth").font(.subheadline.weight(.semibold))
                    DatePicker("Date of birth", selection: birthDate, in: birthRange, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(SelectionBackground(selected: false, cornerRadius: 20))
                    if dobTouched {
                        Text("\(profile.age) years old")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var birthDate: Binding<Date> {
        Binding(get: { profile.birthDate ?? defaultBirthDate },
                set: { picked in
                    profile.birthDate = picked
                    profile.birthYear = Calendar.current.component(.year, from: picked)
                    dobTouched = true
                })
    }

    private var defaultBirthDate: Date {
        Calendar.current.date(from: DateComponents(year: profile.birthYear, month: 6, day: 15))
            ?? birthRange.upperBound
    }

    private var birthRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let oldest = calendar.date(byAdding: .year, value: -100, to: now) ?? now
        let youngest = calendar.date(byAdding: .year, value: -13, to: now) ?? now
        return oldest...youngest
    }

    // 4. Height and weight

    private var sizeStep: some View {
        OnboardingPage("How tall are you, and what do you weigh?",
                       "Both feed every number in the app. You can log a new weight whenever you like.") {
            VStack(spacing: 14) {
                Picker("Units", selection: unitsBinding) {
                    ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HeightWheels(profile: profile)
                WeightWheel(profile: profile)
            }
        }
    }

    private var unitsBinding: Binding<UnitSystem> {
        Binding(get: { profile.units },
                set: { picked in
                    profile.units = picked
                    selectionTick += 1
                })
    }

    // 5. Everyday movement

    private var movementStep: some View {
        OnboardingPage("How much do you move on a normal day?",
                       "Everyday life only, outside any workout. Training is asked separately later, so nothing gets counted twice.") {
            VStack(spacing: 10) {
                ForEach(DailyActivity.allCases) { option in
                    ChoiceRow(symbol: option.symbol,
                              label: option.label,
                              detail: option.detail,
                              selected: profile.dailyActivity == option) {
                        pick { profile.dailyActivity = option }
                    }
                }
            }
        }
    }

    // 6. Target weight

    private var targetWeightStep: some View {
        OnboardingPage("What weight are you aiming at?",
                       "A direction, not a promise. You can move it whenever you like.") {
            VStack(spacing: 16) {
                BigNumber(value: Units.weightString(profile.targetWeightKg, profile.units, decimals: 1),
                          caption: targetDeltaLine,
                          size: 50)
                Slider(value: targetWeightBinding, in: targetWeightRange, step: 0.1)
                HStack {
                    Text(Units.weightString(targetWeightRange.lowerBound, profile.units, decimals: 0))
                    Spacer()
                    Text(Units.weightString(targetWeightRange.upperBound, profile.units, decimals: 0))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

                Callout(symbol: "ruler",
                        text: "A weight that puts your BMI in the healthy range for your height is \(Units.weightString(healthyRange.lowerBound, profile.units, decimals: 0)) to \(Units.weightString(healthyRange.upperBound, profile.units, decimals: 0)). BMI describes a population rather than a person, so treat it as a signpost.")
                if profile.targetWeightKg < healthyRange.lowerBound {
                    Callout(symbol: "exclamationmark.circle",
                            text: "That sits below the healthy range for your height. It can be the right call, and Plate will still do the maths, but it is worth a word with a doctor first.",
                            tint: .orange)
                }
            }
            .onAppear(perform: clampTargetWeight)
        }
    }

    /// The default target the goal implies, at the size that was actually entered. A target the
    /// person has moved themselves is never overwritten.
    private func applyGoalDefaults() {
        guard !targetWeightTouched else { return }
        switch profile.goal {
        case .maintain, .recomp:
            profile.targetWeightKg = profile.weightKg
        case .lose:
            let healthy = BodyComposition.healthyWeightRange(heightCm: profile.heightCm).lowerBound
            profile.targetWeightKg = min(profile.weightKg - 1, max(profile.weightKg - 6, healthy))
        case .gain:
            profile.targetWeightKg = profile.weightKg + 4
        }
    }

    private func clampTargetWeight() {
        let range = targetWeightRange
        profile.targetWeightKg = min(max(profile.targetWeightKg, range.lowerBound), range.upperBound)
    }

    private var targetWeightBinding: Binding<Double> {
        Binding(get: { profile.targetWeightKg },
                set: { picked in
                    profile.targetWeightKg = picked
                    targetWeightTouched = true
                })
    }

    private var healthyRange: ClosedRange<Double> {
        BodyComposition.healthyWeightRange(heightCm: profile.heightCm)
    }

    private var targetWeightRange: ClosedRange<Double> {
        let current = profile.weightKg
        if profile.goal == .gain { return current...(current * 1.35) }
        let lowest = min(current - 2, max(35, current * 0.55))
        return lowest...current
    }

    private var targetDeltaLine: String {
        let change = abs(profile.targetWeightKg - profile.weightKg)
        guard change > 0.05 else { return "the same as today" }
        let word = profile.targetWeightKg < profile.weightKg ? "to lose" : "to gain"
        return "\(Units.weightString(change, profile.units, decimals: 1)) \(word)"
    }

    // 7. Pace

    private var paceStep: some View {
        OnboardingPage("How fast do you want to go?",
                       "Slower is easier to keep and costs less muscle. Plate will not let you pick something unsafe.") {
            VStack(spacing: 16) {
                BigNumber(value: Units.weightString(profile.paceKgPerWeek, profile.units,
                                                    decimals: profile.units == .metric ? 2 : 1),
                          caption: "a week",
                          size: 50)
                Slider(value: $profile.paceKgPerWeek, in: paceRange, step: 0.05)
                HStack {
                    Text("Steady")
                    Spacer()
                    Text("Aggressive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Callout(symbol: "speedometer",
                        text: "The fastest Plate will aim for at your size is \(Units.weightString(paceCeiling, profile.units, decimals: 2)) a week.")
                if isPaceCapped {
                    Callout(symbol: "arrow.down.to.line", text: capReason, tint: .orange)
                }
            }
            .onAppear {
                profile.paceKgPerWeek = min(max(profile.paceKgPerWeek, paceRange.lowerBound), paceRange.upperBound)
            }
        }
    }

    private var paceRange: ClosedRange<Double> {
        profile.goal == .gain ? 0.05...0.6 : 0.1...1.2
    }

    /// What the safety caps allow, read straight from the engine by asking for an absurd pace.
    private var paceCeiling: Double {
        var inputs = profile.inputs
        inputs.paceKgPerWeek = 99
        return NutritionMath.cappedPace(inputs)
    }

    private var isPaceCapped: Bool {
        NutritionMath.cappedPace(profile.inputs) < profile.paceKgPerWeek - 0.001
    }

    private var capReason: String {
        let capped = Units.weightString(NutritionMath.cappedPace(profile.inputs), profile.units, decimals: 2)
        if profile.goal == .gain {
            return "Your plan will aim at \(capped) a week. Muscle cannot be built faster than that at your training age, so anything quicker would arrive as fat."
        }
        return "Your plan will aim at \(capped) a week. Faster than that for your size and the weight coming off is increasingly muscle."
    }

    // 8. Working it out

    private var generatingStep: some View {
        GeneratingView(lines: ["Working out your resting burn",
                               "Adding everyday movement",
                               "Checking a safe pace",
                               "Balancing your macros"]) {
            advance()
        }
    }

    // MARK: The optional runs

    @ViewBuilder private var chunkIntroStep: some View {
        if let chunk {
            OnboardingPage(chunk.heading, chunk.blurb) {
                VStack(spacing: 10) {
                    ForEach(chunk.gains) { gain in
                        gainRow(gain)
                    }
                    if let note = chunk.note {
                        Callout(symbol: "hand.raised", text: note)
                    }
                }
            }
        }
    }

    private func gainRow(_ gain: Chunk.Gain) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: gain.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(gain.title).font(.body.weight(.semibold))
                Text(gain.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(SelectionBackground(selected: false))
    }

    // Training

    private var trainingStyleStep: some View {
        OnboardingPage("Do you train, and what kind?",
                       "Pick the closest. If you do several, choose a bit of everything.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(TrainingStyle.allCases) { option in
                    ChoiceCard(symbol: option.symbol,
                               label: option.label,
                               selected: profile.trainingStyle == option) {
                        pick { chooseTraining(option) }
                    }
                }
            }
        }
    }

    private func chooseTraining(_ style: TrainingStyle) {
        profile.trainingStyle = style
        if style == .none {
            profile.trainingDaysPerWeek = 0
            profile.experience = .none
            if profile.cycling == .trainingDays { profile.cycling = .even }
        } else if profile.trainingDaysPerWeek == 0 {
            profile.trainingDaysPerWeek = 3
        }
    }

    private var trainingLoadStep: some View {
        OnboardingPage(profile.trainingStyle.loadQuestion,
                       "A session is one workout, from warm up to the end. Rough numbers are fine: Plate turns them into calories and adds them to your day.") {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Days a week").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(profile.trainingDaysPerWeek)")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .contentTransition(.numericText())
                    }
                    HStack(spacing: 6) {
                        ForEach(0...7, id: \.self) { days in
                            dayPill(days)
                        }
                    }
                }
                .padding(16)
                .background(SelectionBackground(selected: false))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("A session lasts").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(profile.trainingMinutes) min")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .contentTransition(.numericText())
                    }
                    Slider(value: minutesBinding, in: 15...120, step: 15)
                    HStack {
                        Text("15 min").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("2 hours").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(SelectionBackground(selected: false))

                Callout(symbol: "flame.fill", text: trainingBurnLine, tint: .accentColor)
            }
        }
    }

    private func dayPill(_ days: Int) -> some View {
        Button {
            pick { profile.trainingDaysPerWeek = days }
        } label: {
            Text("\(days)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(profile.trainingDaysPerWeek == days ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(profile.trainingDaysPerWeek == days
                              ? Color.accentColor
                              : Color.primary.opacity(0.06))
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(days) days a week")
    }

    private var minutesBinding: Binding<Double> {
        Binding(get: { Double(profile.trainingMinutes) },
                set: { profile.trainingMinutes = Int($0.rounded()) })
    }

    /// One number in one unit. The daily figure is the one that matters, because the daily figure is
    /// what the calorie budget is made of.
    private var trainingBurnLine: String {
        let perDay = Int(NutritionMath.trainingKcalPerDay(profile.inputs).rounded())
        guard perDay > 0 else { return "Pick at least one day to see what your training adds." }
        return "That adds about \(perDay) calories to your daily budget."
    }

    private var experienceStep: some View {
        OnboardingPage("How long have you been training?",
                       "This sets how fast muscle can realistically be added, which is what caps a gaining plan.") {
            VStack(spacing: 10) {
                ForEach(TrainingExperience.allCases) { option in
                    ChoiceRow(symbol: experienceSymbol(option),
                              label: option.label,
                              detail: experienceDetail(option),
                              selected: profile.experience == option) {
                        pick { profile.experience = option }
                    }
                }
            }
        }
    }

    private func experienceSymbol(_ option: TrainingExperience) -> String {
        switch option {
        case .none: return "figure.stand"
        case .beginner: return "leaf.fill"
        case .intermediate: return "flame.fill"
        case .advanced: return "trophy.fill"
        }
    }

    private func experienceDetail(_ option: TrainingExperience) -> String {
        "At best around \(Units.weightString(option.monthlyMuscleKg, profile.units, decimals: 1)) of muscle a month."
    }

    // Body fat

    private var tapeStep: some View {
        OnboardingPage("Measure up",
                       "Relaxed, at the end of a normal breath out. Measuring the same spots every time matters more than being exact.") {
            VStack(spacing: 12) {
                TapeField(field: tapeField("neck"), cm: $profile.neckCm, units: profile.units)
                TapeField(field: tapeField("waist"), cm: $profile.waistCm, units: profile.units)
                if profile.sex == .female {
                    TapeField(field: tapeField("hip"), cm: $profile.hipCm, units: profile.units)
                }
                tapeResult
            }
        }
    }

    private func tapeField(_ key: String) -> BodyMeasurement.Field {
        BodyMeasurement.fields.first { $0.key == key }
            ?? BodyMeasurement.Field(key: key, label: key.capitalized, symbol: "ruler", tip: "")
    }

    private var tapeBodyFat: Double? {
        guard let neck = profile.neckCm, let waist = profile.waistCm else { return nil }
        return BodyComposition.navyBodyFat(sex: profile.sex, heightCm: profile.heightCm,
                                           neckCm: neck, waistCm: waist, hipCm: profile.hipCm)
    }

    private var bodyFatFloor: Double { BodyComposition.healthyFloor(for: profile.sex) }

    @ViewBuilder private var tapeResult: some View {
        if let percent = tapeBodyFat {
            VStack(spacing: 6) {
                Text(String(format: "%.1f%% body fat", percent))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let band = BodyComposition.band(for: percent, sex: profile.sex) {
                    Text(band.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(band.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(SelectionBackground(selected: true))
        } else {
            Callout(symbol: "ruler",
                    text: profile.sex == .female
                        ? "Fill in all three and your body fat appears here."
                        : "Fill in both and your body fat appears here.")
        }
    }

    private var targetBodyFatStep: some View {
        OnboardingPage("What would you like to get down to?",
                       "Body fat is a better target than weight, because it does not care whether the scale moves.") {
            VStack(spacing: 16) {
                BigNumber(value: String(format: "%.1f%%", targetBodyFatValue),
                          caption: targetBandName,
                          size: 50)
                Slider(value: targetBodyFatBinding, in: bodyFatFloor...(tapeBodyFat ?? bodyFatFloor + 1), step: 0.5)
                HStack {
                    Text(String(format: "%.0f%% floor", bodyFatFloor))
                    Spacer()
                    Text(String(format: "now %.1f%%", tapeBodyFat ?? 0))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

                if let implied = weightAtTargetBodyFat {
                    Callout(symbol: "scalemass",
                            text: "Holding every gram of muscle, that lands you at about \(Units.weightString(implied, profile.units, decimals: 1)).")
                    Button {
                        pick {
                            profile.targetWeightKg = implied
                            targetWeightTouched = true
                        }
                    } label: {
                        Label("Use that as my target weight", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(FlowButtonStyle(prominent: false))
                }
                Callout(symbol: "info.circle",
                        text: "Below about \(Int(bodyFatFloor))% most people find hormones, mood and sleep suffer, so the slider stops there.")
            }
            .onAppear {
                if profile.targetBodyFat == nil, let current = tapeBodyFat {
                    profile.targetBodyFat = ((current + bodyFatFloor) / 2 * 2).rounded() / 2
                }
            }
        }
    }

    /// Clamped, because the tape can be edited after a target has been set.
    private var targetBodyFatValue: Double {
        let chosen = profile.targetBodyFat ?? tapeBodyFat ?? bodyFatFloor
        return min(max(chosen, bodyFatFloor), tapeBodyFat ?? bodyFatFloor + 1)
    }

    private var targetBodyFatBinding: Binding<Double> {
        Binding(get: { targetBodyFatValue }, set: { profile.targetBodyFat = $0 })
    }

    private var targetBandName: String {
        BodyComposition.band(for: targetBodyFatValue, sex: profile.sex)?.name ?? "body fat"
    }

    private var weightAtTargetBodyFat: Double? {
        guard let current = tapeBodyFat else { return nil }
        return BodyComposition.weightAtBodyFat(currentWeightKg: profile.weightKg,
                                               currentBodyFat: current,
                                               targetBodyFat: targetBodyFatValue)
    }

    // How you eat

    private var dietStep: some View {
        OnboardingPage("How do you like to eat?",
                       "This sets how the calories split into protein, carbs and fat. None of them lose weight faster than the others.") {
            VStack(spacing: 10) {
                ForEach(DietStyle.allCases) { option in
                    ChoiceRow(label: option.label,
                              detail: option.detail,
                              selected: profile.diet == option) {
                        pick { profile.diet = option }
                    }
                }
            }
        }
    }

    private var avoidsStep: some View {
        OnboardingPage("Anything you do not eat?",
                       "Plate keeps these out of its suggestions. Type your own, or tap a common one.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("Add a food", text: $newAvoid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { addAvoid(newAvoid) }
                        .padding(14)
                        .background(SelectionBackground(selected: false, cornerRadius: 16))
                    Button {
                        addAvoid(newAvoid)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(newAvoid.trimmed.isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(newAvoid.trimmed.isEmpty)
                    .accessibilityLabel("Add food to avoid")
                }

                if !profile.avoids.isEmpty {
                    WrapLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(profile.avoids, id: \.self) { item in
                            ChoiceChip(label: item, symbol: "xmark", selected: true) {
                                pick { profile.avoids = profile.avoids.filter { $0 != item } }
                            }
                        }
                    }
                }

                Text("Common ones").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                WrapLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(commonAvoids, id: \.self) { suggestion in
                        let chosen = profile.avoids.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
                        ChoiceChip(label: suggestion, selected: chosen) {
                            if chosen {
                                pick { profile.avoids = profile.avoids.filter { $0.caseInsensitiveCompare(suggestion) != .orderedSame } }
                            } else {
                                addAvoid(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }

    private var commonAvoids: [String] {
        ["dairy", "gluten", "nuts", "shellfish", "pork", "eggs", "soy"]
    }

    private func addAvoid(_ raw: String) {
        // The list is stored comma separated, so a comma typed by hand would split one food into two.
        let item = raw.replacingOccurrences(of: ",", with: " ").trimmed
        guard !item.isEmpty else { return }
        guard !profile.avoids.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) else {
            newAvoid = ""
            return
        }
        pick { profile.avoids = profile.avoids + [item] }
        newAvoid = ""
    }

    private var mealPatternStep: some View {
        OnboardingPage("How do your days usually look?",
                       "Meal timing does not change what you lose. It changes whether you make it to bedtime without raiding the fridge.") {
            VStack(spacing: 10) {
                ForEach(MealPattern.allCases) { option in
                    ChoiceRow(symbol: "\(option.mealCount).circle.fill",
                              label: option.label,
                              detail: mealPatternDetail(option),
                              selected: profile.mealPattern == option) {
                        pick { profile.mealPattern = option }
                    }
                }
            }
        }
    }

    private func mealPatternDetail(_ option: MealPattern) -> String {
        // The live plan, not the stored target: nothing has been recalculated at this point.
        let each = profile.plan.calories / max(option.mealCount, 1)
        return option.mealCount == 1
            ? "Everything in one sitting."
            : "Roughly \(each) calories a sitting at your target."
    }

    private var cyclingStep: some View {
        OnboardingPage("Same calories every day?",
                       "The weekly total is identical either way. Uneven days just fit some lives better.") {
            VStack(spacing: 10) {
                ForEach(cyclingOptions) { option in
                    ChoiceRow(symbol: cyclingSymbol(option),
                              label: option.label,
                              detail: option.detail,
                              selected: profile.cycling == option) {
                        pick { profile.cycling = option }
                    }
                }
                if let preview = splitPreview {
                    Callout(symbol: "calendar", text: preview, tint: .accentColor)
                }
            }
        }
    }

    private var cyclingOptions: [CalorieCycling] {
        CalorieCycling.allCases.filter { !($0 == .trainingDays && profile.trainingDaysPerWeek == 0) }
    }

    private func cyclingSymbol(_ option: CalorieCycling) -> String {
        switch option {
        case .even: return "equal.circle.fill"
        case .trainingDays: return "dumbbell.fill"
        case .weekends: return "calendar"
        }
    }

    private var splitPreview: String? {
        guard let split = NutritionMath.daySplit(calories: profile.plan.calories,
                                                 cycling: profile.cycling,
                                                 trainingDaysPerWeek: profile.trainingDaysPerWeek) else { return nil }
        return "\(split.label): about \(split.higher) calories. Every other day: \(split.lower)."
    }

    // Habits

    private var focusStep: some View {
        OnboardingPage("Anywhere in particular?",
                       "Up to three. This changes the advice Plate gives you, not the calorie maths.") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                          spacing: 10) {
                    ForEach(BodyArea.allCases) { area in
                        let chosen = profile.focusAreas.contains(area)
                        ChoiceCard(symbol: area.symbol, label: area.label, selected: chosen) {
                            toggleArea(area)
                        }
                        .disabled(!chosen && profile.focusAreas.count >= 3)
                        .opacity(!chosen && profile.focusAreas.count >= 3 ? 0.4 : 1)
                    }
                }
                if !profile.focusAreas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("And there you want to be").font(.subheadline.weight(.semibold))
                        Picker("Area goal", selection: areaGoalBinding) {
                            ForEach(AreaGoal.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Text(FocusGuidance.spotReductionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggleArea(_ area: BodyArea) {
        var chosen = profile.focusAreas
        if let index = chosen.firstIndex(of: area) {
            chosen.remove(at: index)
        } else if chosen.count < 3 {
            chosen.append(area)
        } else {
            return
        }
        pick { profile.focusAreas = chosen }
    }

    private var areaGoalBinding: Binding<AreaGoal> {
        Binding(get: { profile.areaGoal },
                set: { picked in
                    profile.areaGoal = picked
                    selectionTick += 1
                })
    }

    private var drinksStep: some View {
        OnboardingPage("How many drinks in a normal week?",
                       "Not a judgment, just arithmetic. Alcohol carries calories with almost nothing useful attached.") {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    BigNumber(value: "\(profile.drinksPerWeek)",
                              caption: profile.drinksPerWeek == 1 ? "drink a week" : "drinks a week",
                              size: 54)
                    Stepper("Drinks per week", value: drinksBinding, in: 0...30)
                        .labelsHidden()
                }
                .padding(16)
                .background(SelectionBackground(selected: false))
                Callout(symbol: "wineglass", text: drinksLine)
            }
        }
    }

    private var drinksBinding: Binding<Int> {
        Binding(get: { profile.drinksPerWeek },
                set: { value in
                    profile.drinksPerWeek = value
                    selectionTick += 1
                })
    }

    private var drinksLine: String {
        let count = profile.drinksPerWeek
        guard count > 0 else { return "Nothing to count." }
        let low = count * 100
        let high = count * 150
        return "Around \(low) to \(high) calories a week, which is \(low / 7) to \(high / 7) a day. Log them like any other food and the numbers stay honest."
    }

    private var obstaclesStep: some View {
        OnboardingPage("What has got in the way before?",
                       "Pick as many as fit. Plate uses them to decide which nudges to show, nothing else.") {
            VStack(alignment: .leading, spacing: 14) {
                WrapLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Obstacle.allCases) { option in
                        ChoiceChip(label: option.label,
                                   selected: profile.obstacles.contains(option)) {
                            toggleObstacle(option)
                        }
                    }
                }
                if let latest = profile.obstacles.last {
                    Callout(symbol: "lightbulb", text: latest.tip, tint: .accentColor)
                }
            }
        }
    }

    private func toggleObstacle(_ option: Obstacle) {
        var chosen = profile.obstacles
        if let index = chosen.firstIndex(of: option) {
            chosen.remove(at: index)
        } else {
            chosen.append(option)
        }
        pick { profile.obstacles = chosen }
    }

    // Setup

    private var healthStep: some View {
        OnboardingPage("Apple Health",
                       "Plate can write every meal to Health and read your steps, workouts and weight back.") {
            VStack(spacing: 12) {
                ToggleCard(symbol: "heart.fill",
                           title: "Sync with Apple Health",
                           detail: "Meals go out as they are logged. Weight and workouts come back in, so you only type things once.",
                           isOn: $profile.writeToHealth)
                ToggleCard(symbol: "flame.fill",
                           title: "Add workout calories",
                           detail: "Adds active energy from Health to the day's budget. Watches overcount, so most people leave this off.",
                           isOn: $profile.addExerciseCalories)
                ToggleCard(symbol: "arrow.uturn.forward",
                           title: "Roll unused calories over",
                           detail: "Up to 250 calories from yesterday land in today's budget.",
                           isOn: $profile.rolloverCalories)
            }
        }
    }

    private var apiKeyStep: some View {
        OnboardingPage("Photo logging",
                       "Plate sends meal photos to a hosted model for the estimate. Pick a provider and paste its key to turn that on. Barcodes, search and manual entry all work without it.") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { _, picked in
                    AIProvider.current = picked
                    apiKey = Keychain.get(picked.keyAccount) ?? ""
                    keyStatus = .idle
                }

                SecureField(provider.keyPlaceholder, text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(SelectionBackground(selected: false, cornerRadius: 16))

                HStack {
                    Button("Test key") { testKey() }
                        .disabled(apiKey.trimmed.isEmpty)
                    Spacer()
                    switch keyStatus {
                    case .idle: EmptyView()
                    case .checking: SwiftUI.ProgressView()
                    case .ok: Label("Works", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let why): Text(why).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
                .font(.subheadline)

                Text("\(provider.consoleHint) Keys are stored in the iOS keychain and only ever sent to \(provider.host).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func testKey() {
        keyStatus = .checking
        let key = apiKey.trimmed
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

    // MARK: The plan

    private var planStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(lastChunk == nil ? "Your plan is ready" : "Your plan, updated")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(plan.calories)")
                        .font(.system(size: 78, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("calories a day")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)

                changeCallout

                HStack(alignment: .top, spacing: 10) {
                    MacroRing(name: "Protein", grams: plan.protein, share: macroShares.protein, color: .protein)
                    MacroRing(name: "Carbs", grams: plan.carbs, share: macroShares.carbs, color: .carbs)
                    MacroRing(name: "Fat", grams: plan.fat, share: macroShares.fat, color: .fat)
                }
                .frame(maxWidth: .infinity)
                .card()

                HStack(alignment: .top, spacing: 8) {
                    StatBlock(title: "Resting burn", value: "\(plan.bmr)", unit: "kcal")
                    Divider()
                    StatBlock(title: "Daily burn", value: "\(plan.tdee)", unit: "kcal")
                    Divider()
                    StatBlock(title: plan.dailyDelta < 0 ? "Deficit" : (plan.dailyDelta > 0 ? "Surplus" : "Even"),
                              value: "\(abs(plan.dailyDelta))",
                              unit: "kcal a day")
                }
                .card()

                VStack(spacing: 10) {
                    planRow("speedometer", "Aiming at", paceSummary)
                    if let date = projectedDate {
                        Divider()
                        planRow("flag.checkered", "On this plan you reach \(Units.weightString(profile.targetWeightKg, profile.units, decimals: 1)) around",
                                date.formatted(.dateTime.month(.wide).day().year()))
                    }
                    Divider()
                    planRow("drop.fill", "Water", "\(plan.waterMl) ml a day")
                    Divider()
                    planRow("leaf.fill", "Fiber", "\(plan.fiber) g a day")
                }
                .card()

                if let note = plan.note {
                    Callout(symbol: "hand.raised", text: note, tint: .orange)
                }

                refineCard

                VStack(spacing: 8) {
                    Text("Resting burn from \(plan.method).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { showSources = true } label: {
                        Label("How every number here is worked out", systemImage: "book")
                            .font(.footnote.weight(.medium))
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder private var changeCallout: some View {
        if let chunk = lastChunk, let before = planBefore {
            Callout(symbol: "sparkles", text: changeLine(chunk, from: before, to: plan), tint: .accentColor)
        }
    }

    /// What a run of questions actually moved. Saying nothing moved is worth as much as saying what
    /// did, because it tells you the defaults were already right for you.
    private func changeLine(_ chunk: Chunk, from before: NutritionMath.Plan, to now: NutritionMath.Plan) -> String {
        var moves: [String] = []
        if before.calories != now.calories { moves.append("calories from \(before.calories) to \(now.calories)") }
        if before.protein != now.protein { moves.append("protein from \(before.protein)g to \(now.protein)g") }
        if before.method != now.method { moves.append("your resting burn onto \(now.method)") }
        guard !moves.isEmpty else {
            return "\(chunk.title) answered. Nothing moved, which means the defaults already matched you."
        }
        return "\(chunk.title) answered. That moved \(sentenceList(moves))."
    }

    private func sentenceList(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

    private var refineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Make it sharper")
                    .font(.subheadline.weight(.semibold))
                Text("Optional. Each part is a few questions, says what it improves before it starts, and hands you straight back here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Self.chunks) { chunk in
                Button { start(chunk) } label: { chunkRow(chunk) }
                    .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func chunkRow(_ chunk: Chunk) -> some View {
        let done = doneChunks.contains(chunk.id)
        return HStack(spacing: 12) {
            Image(systemName: chunk.symbol)
                .font(.body)
                .foregroundStyle(done ? Color.secondary : Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(chunk.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(chunk.promise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func planRow(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    private var macroShares: (protein: Double, carbs: Double, fat: Double) {
        let total = Double(plan.proteinKcal + plan.carbKcal + plan.fatKcal)
        guard total > 0 else { return (0, 0, 0) }
        return (Double(plan.proteinKcal) / total,
                Double(plan.carbKcal) / total,
                Double(plan.fatKcal) / total)
    }

    private var paceSummary: String {
        switch profile.goal {
        case .maintain: return "holding steady"
        case .recomp: return "a small deficit, hard training"
        case .lose, .gain:
            let rate = Units.weightString(plan.paceKgPerWeek, profile.units,
                                          decimals: profile.units == .metric ? 2 : 1)
            return "\(rate) a week"
        }
    }

    private var projectedDate: Date? {
        guard profile.goal.changesWeight, plan.calories > 0 else { return nil }
        return NutritionMath.projectedGoalDate(for: profile.inputs,
                                               calorieTarget: plan.calories,
                                               targetKg: profile.targetWeightKg)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
