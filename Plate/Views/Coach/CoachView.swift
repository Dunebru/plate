import SwiftData
import SwiftUI

/// Ask questions about your own numbers.
///
/// Everything shown here is answered from the brief `Coach` assembles out of the store, so the
/// answers are about this person rather than about nutrition in general. The conversation is not
/// saved: it costs almost nothing to ask again, and keeping a transcript of someone's questions
/// about their own body is not something this app should be doing.
struct CoachView: View {
    @Bindable var profile: Profile
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @StateObject private var health = HealthStore.shared

    @State private var turns: [Coach.Turn] = []
    @State private var question = ""
    @State private var thinking = false
    @State private var error: String?
    @State private var answered = 0
    @FocusState private var typing: Bool

    private var hasKey: Bool { (Keychain.get(AIProvider.current.keyAccount) ?? "").isEmpty == false }

    var body: some View {
        NavigationStack {
            Group {
                if !hasKey {
                    EmptyStateView(symbol: "key", title: "Add a key first",
                                   message: "Asking questions uses the same key as photo scanning. Settings has the setup, and a question costs a fraction of a scan.")
                } else {
                    conversation
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask")
            .toolbar {
                if !turns.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { withAnimation(.flow) { turns = []; error = nil } }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: answered)
            .task { await health.refreshToday() }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if turns.isEmpty { opener }
                    ForEach(turns) { turn in
                        bubble(turn).id(turn.id)
                    }
                    if thinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reading your numbers").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .id("thinking")
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .onChange(of: turns.count) { _, _ in
                withAnimation(.flow) { proxy.scrollTo(turns.last?.id, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask about your own data")
                .font(.title3.weight(.semibold))
            Text("It can see your targets, the last two weeks of logging, your trend weight and what you have been eating. It cannot see anything else, and it is not a doctor.")
                .font(.subheadline).foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Coach.suggestions(profile: profile, hasMeals: !meals.isEmpty), id: \.self) { prompt in
                    Button { ask(prompt) } label: {
                        HStack {
                            Text(prompt).font(.subheadline).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.top, 4)
        }
    }

    private func bubble(_ turn: Coach.Turn) -> some View {
        HStack {
            if turn.role == .you { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.subheadline)
                .foregroundStyle(turn.role == .you ? Color.white : Color.primary)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(turn.role == .you ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .textSelection(.enabled)
            if turn.role == .coach { Spacer(minLength: 40) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask a question", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .textFieldStyle(.plain)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit { ask(question) }

            Button { ask(question) } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(PressableStyle())
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
            .opacity(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking ? 0.4 : 1)
            .animation(.flow, value: question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        typing = false
        error = nil
        question = ""
        let history = turns
        withAnimation(.flow) {
            turns.append(Coach.Turn(role: .you, text: trimmed))
            thinking = true
        }
        Task {
            do {
                // The same figure Today adds to the ring, so the two screens quote one number.
                let inputs = profile.inputs
                let assumed = NutritionMath.tdee(inputs) - NutritionMath.bmr(inputs)
                let earned = Int(max(0, health.activeEnergyToday - assumed).rounded())
                let brief = Coach.brief(profile: profile, meals: meals, weights: weights,
                                        extraBurnToday: earned)
                let reply = try await Coach().answer(question: trimmed, brief: brief, history: history)
                withAnimation(.flow) {
                    turns.append(Coach.Turn(role: .coach, text: reply))
                    thinking = false
                }
                answered += 1
            } catch {
                withAnimation(.flow) {
                    thinking = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
