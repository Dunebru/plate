import SwiftUI

/// Everything Plate has read out of Apple Health, with the source of every number beside it.
///
/// The burn card is the only one that changes anything. Sleep and heart rate are here because a
/// hard week and a plateau look identical on a scale and different on a wrist, and that is worth
/// being able to see. They are shown and not interpreted: Plate is a calorie app, and what your
/// heart rate variability means is not its business.
struct HealthSignalsView: View {
    let profile: Profile
    @StateObject private var health = HealthStore.shared
    @State private var refreshing = false

    private var prediction: HealthSignals.Prediction { .init(profile.inputs) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if health.signals.hasAnything {
                    if let burn = health.signals.burn { burnCard(burn) }
                    if let training = health.signals.training { trainingCard(training) }
                    if !health.signals.recovery.isEmpty { recoveryCard(health.signals.recovery) }
                    if let readAt = health.signals.readAt { footer(readAt) }
                } else {
                    EmptyStateView(symbol: "applewatch.slash",
                                   title: "Nothing to read yet",
                                   message: emptyMessage)
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("From Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh()
                } label: {
                    if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(refreshing)
            }
        }
        .task { refresh() }
    }

    private var emptyMessage: String {
        "A Whoop, an Apple Watch or any other app that writes to Apple Health will show up here. "
        + "If you have one, check that it is switched on in the Health app under Sharing, and that "
        + "you allowed Plate to read it."
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            await HealthStore.shared.refreshSignals(prediction: prediction)
            refreshing = false
        }
    }

    // MARK: Burn

    private func burnCard(_ burn: HealthSignals.MeasuredBurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressCardTitle(text: "Burn from \(burn.source.label)", symbol: "flame")
            ProgressHeadline(value: "\(burn.tdee) kcal", caption: burnCaption(burn))
            ProgressConfidenceBar(confidence: burn.confidence)

            HStack(alignment: .top, spacing: 18) {
                stat(burn.basis == .wholeDay ? "Resting" : "Rest of the day", "\(burn.restingKcal) kcal")
                stat(burn.basis == .wholeDay ? "Moving" : "Training", "\(burn.activeKcal) kcal")
                stat("Equation says", "\(Int(prediction.tdee.rounded())) kcal")
                Spacer(minLength: 0)
            }

            ProgressNote(text: burn.basis == .wholeDay
                         ? "Resting and moving are the two halves of a day, so they add up. Plate never adds its own resting estimate on top of a measured one."
                         : "Health has your sessions but nothing about the hours between them, so only training is measured here. The rest of the day is still the equation, and the two do not overlap.")
            ProgressNote(text: "This sets the starting figure your logging is measured against, not your target. The scale and your food log still have the last word.",
                         symbol: "arrow.triangle.branch")
        }
        .card()
    }

    private func burnCaption(_ burn: HealthSignals.MeasuredBurn) -> String {
        switch burn.basis {
        case .wholeDay:
            return "Averaged over \(burn.days) whole \(burn.days == 1 ? "day" : "days"). Today is left out while it is still running."
        case .workoutsOnly:
            return "Your \(burn.sessions) recorded \(burn.sessions == 1 ? "session" : "sessions") spread across \(burn.days) days, in place of the estimate from your setup answers."
        }
    }

    // MARK: Training

    private func trainingCard(_ training: HealthSignals.TrainingWeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressCardTitle(text: "Training", symbol: "figure.run")
            ProgressHeadline(value: "\(sessionText(training.sessions)) a week",
                             caption: "About \(training.averageMinutes) minutes a session, from the workouts in Health.")
            if profile.trainingStyle != .none {
                HStack(alignment: .top, spacing: 18) {
                    stat("Your plan assumes", "\(profile.trainingDaysPerWeek) x \(profile.trainingMinutes) min")
                    Spacer(minLength: 0)
                }
                if disagrees(training) {
                    ProgressNote(text: "Health and your setup answers disagree. Neither is automatically right, so nothing has been changed. Movement in Settings is where to adjust it.",
                                 symbol: "questionmark.circle")
                }
            }
            if !health.signals.workouts.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(health.signals.workouts.prefix(5)) { workout in
                    workoutRow(workout)
                }
            }
        }
        .card()
    }

    private func sessionText(_ sessions: Double) -> String {
        let whole = sessions.rounded()
        let value = abs(sessions - whole) < 0.05 ? String(Int(whole)) : String(format: "%.1f", sessions)
        return "\(value) \(sessions == 1 ? "session" : "sessions")"
    }

    /// Worth pointing out only when the gap is big enough to move a target.
    private func disagrees(_ training: HealthSignals.TrainingWeek) -> Bool {
        abs(training.sessions - Double(profile.trainingDaysPerWeek)) >= 1.5
            || abs(training.averageMinutes - profile.trainingMinutes) >= 20
    }

    private func workoutRow(_ workout: HealthSignals.Workout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(workout.kind).font(.subheadline)
                Text("\(workout.date.dayTitle) \u{00b7} \(workout.source.label)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(workout.kcal.map { "\($0) kcal" } ?? "\(workout.minutes) min")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    // MARK: Recovery

    private func recoveryCard(_ recovery: HealthSignals.Recovery) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressCardTitle(text: "Context", symbol: "bed.double")
            VStack(spacing: 10) {
                if let hours = recovery.sleepHours {
                    metric("Last night", sleepText(hours), recovery.sleepSource)
                }
                if let rhr = recovery.restingHeartRate {
                    metric("Resting heart rate", "\(rhr) bpm", recovery.restingHeartRateSource)
                }
                if let hrv = recovery.hrvMs {
                    metric("Heart rate variability", "\(hrv) ms", recovery.hrvSource)
                }
                if let rate = recovery.respiratoryRate {
                    metric("Breaths a minute", String(format: "%.1f", rate), recovery.respiratoryRateSource)
                }
            }
            ProgressNote(text: "None of these change a calorie target and Plate will not pretend they do. They are here so a hard week and a stalled week are telling apart.")
        }
        .card()
    }

    private func sleepText(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int(((hours - Double(h)) * 60).rounded())
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }

    private func metric(_ label: String, _ value: String, _ source: HealthSignals.Source?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline)
                if let source {
                    Text(source.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    // MARK: Footer

    private func footer(_ readAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressNote(text: "Last read \(readAt.formatted(date: .omitted, time: .shortened)).",
                         symbol: "clock")
            ProgressNote(text: "When several devices write the same hours, Plate believes one of them and ignores the rest. Health does not do that for you, and adding them together would roughly double your day.",
                         symbol: "square.on.square")
        }
        .padding(.horizontal, 4)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}
