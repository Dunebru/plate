import SwiftUI

// Small pieces the Progress tab reuses, so the screen itself reads as a list of cards.

/// How much weight history a chart shows. Anchored to the last reading rather than today, so a
/// break from weighing in does not leave an empty chart.
enum ProgressRange: String, CaseIterable, Identifiable {
    case month, quarter, half, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "30D"
        case .quarter: return "90D"
        case .half: return "180D"
        case .all: return "All"
        }
    }

    var days: Int? {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .half: return 180
        case .all: return nil
        }
    }

    /// Earliest day to show, or nil for everything there is.
    func start(endingOn end: Date) -> Date? {
        guard let days else { return nil }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end))
    }
}

/// Weight in whichever unit the owner reads. Deltas convert the same way as weights because the
/// pound to kilogram relation has no offset.
struct ProgressWeightFormat {
    var units: UnitSystem

    var suffix: String { units == .metric ? "kg" : "lb" }

    func display(_ kg: Double) -> Double { units == .metric ? kg : Units.kgToLb(kg) }

    func string(_ kg: Double, decimals: Int = 1) -> String { Units.weightString(kg, units, decimals: decimals) }

    /// Unsigned size of a gap, for sentences that say which way it went in words.
    func gap(_ kg: Double) -> String { Units.weightString(abs(kg), units) }

    func rate(_ kgPerWeek: Double) -> String {
        String(format: "%+.2f %@ a week", display(kgPerWeek), suffix)
    }
}

/// One day of the calorie log, shaped for Swift Charts.
struct ProgressDayCalories: Identifiable {
    var day: Date
    var calories: Double?
    var id: Date { day }
}

struct ProgressCardTitle: View {
    var text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.caption.weight(.semibold))
            }
            Text(text).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }
}

/// The number the card is about, with the sentence that qualifies it underneath.
struct ProgressHeadline: View {
    var value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Colored spine down the side of a card. Carries the verdict without shouting it.
struct ProgressAccentBar: View {
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 4)
    }
}

struct ProgressStatTile: View {
    var value: String
    var label: String
    var symbol: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

/// How much the measured burn can be trusted. Three steps, because a percentage would imply a
/// precision this does not have.
struct ProgressConfidenceBar: View {
    var confidence: Double

    private var steps: Int { confidence >= 0.75 ? 3 : (confidence >= 0.5 ? 2 : 1) }

    private var label: String {
        switch steps {
        case 3: return "Strong"
        case 2: return "Fair"
        default: return "Low"
        }
    }

    private var color: Color {
        switch steps {
        case 3: return .green
        case 2: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i < steps ? color : Color.primary.opacity(0.12))
                        .frame(width: 18, height: 5)
                }
            }
            Text("\(label) confidence").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(label)")
    }
}

/// A quiet line of reasoning under a card, for the sentence that stops a number being misread.
struct ProgressNote: View {
    var text: String
    var symbol: String = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption2)
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

struct ProgressMetricRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// Stands in for a chart that has nothing to draw yet, sized so the card does not collapse.
struct ProgressChartPlaceholder: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Weight entry in the owner's unit. The Progress tab keeps its own so the weigh in sheet does not
/// depend on the onboarding flow.
struct ProgressWeightField: View {
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
            NumberField(title: units == .metric ? "kg" : "lb", value: $shown, decimals: 1)
                .frame(width: 80)
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
